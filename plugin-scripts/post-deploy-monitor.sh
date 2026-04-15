#!/usr/bin/env bash
# PostToolUse hook for Bash: detects tfy apply/deploy commands,
# records the deployment, and polls until terminal state.
#
# Receives hook JSON on stdin with tool_input.command and tool_output.
# Exit 0 = hook ran successfully (output feeds back to conversation).
# Exit 2 = not a deploy command, no opinion.

set -euo pipefail

# --- Read hook input ---
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# --- Detect deploy commands ---
# Match: tfy apply, tfy deploy (with or without -f), REST API deploy via tfy-api.sh or curl
is_deploy=false
app_name=""
manifest_file=""

if [[ "$COMMAND" =~ tfy[[:space:]]+(apply|deploy)[[:space:]]+-f[[:space:]]+([^[:space:]]+) ]]; then
  is_deploy=true
  manifest_file="${BASH_REMATCH[2]}"
  # Try to extract app name from the manifest file
  if [[ -f "$manifest_file" ]]; then
    app_name=$(grep -m1 '^name:' "$manifest_file" 2>/dev/null | sed 's/^name:[[:space:]]*//' || true)
    # Strip surrounding YAML quotes (e.g., name: "my-app" -> my-app)
    app_name="${app_name#\"}" && app_name="${app_name%\"}"
    app_name="${app_name#\'}" && app_name="${app_name%\'}"
  fi
elif [[ "$COMMAND" =~ tfy[[:space:]]+(apply|deploy)([[:space:]]|$) ]]; then
  # tfy deploy / tfy apply without -f (working directory deploy)
  is_deploy=true
  # Look for common manifest files in the working directory
  for candidate in truefoundry.yaml servicefoundry.yaml deploy.yaml; do
    if [[ -f "$candidate" ]]; then
      manifest_file="$candidate"
      app_name=$(grep -m1 '^name:' "$candidate" 2>/dev/null | sed 's/^name:[[:space:]]*//' || true)
      # Strip surrounding YAML quotes (e.g., name: "my-app" -> my-app)
      app_name="${app_name#\"}" && app_name="${app_name%\"}"
      app_name="${app_name#\'}" && app_name="${app_name%\'}"
      break
    fi
  done
elif [[ "$COMMAND" =~ tfy-api\.sh[[:space:]]+PUT[[:space:]]+.*/api/svc/v1/apps ]]; then
  is_deploy=true
  # Extract name from JSON body in the command (macOS-compatible, no grep -P)
  app_name=$(echo "$COMMAND" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' 2>/dev/null | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"//;s/"//' || true)
elif [[ "$COMMAND" =~ curl[[:space:]].*(/api/svc/v1/apps|/api/svc/v1/application) ]]; then
  # REST API deploys via curl
  is_deploy=true
  app_name=$(echo "$COMMAND" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' 2>/dev/null | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"//;s/"//' || true)
elif [[ "$COMMAND" =~ \|[[:space:]]*tfy[[:space:]]+(apply|deploy) ]]; then
  # tfy apply/deploy with piped input (e.g., cat manifest.yaml | tfy apply)
  is_deploy=true
fi

if ! $is_deploy; then
  exit 2
fi

# --- Load credentials ---
if [[ -f ".env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line#export }"
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      key="${line%%=*}"
      value="${line#*=}"
      # Only strip matching outer quotes (avoid over-stripping mixed quotes)
      if [[ "$value" =~ ^\".*\"$ ]]; then
        value="${value#\"}" && value="${value%\"}"
      elif [[ "$value" =~ ^\'.*\'$ ]]; then
        value="${value#\'}" && value="${value%\'}"
      fi
      export "$key=$value"
    fi
  done < .env
fi

# Bridge Claude plugin userConfig values (same pattern as session-start.sh)
# Each hook runs in a separate shell process, so session-start.sh exports don't persist.
TFY_BASE_URL="${TFY_BASE_URL:-${CLAUDE_PLUGIN_OPTION_TFY_BASE_URL:-}}"
TFY_API_KEY="${TFY_API_KEY:-${CLAUDE_PLUGIN_OPTION_TFY_API_KEY:-}}"

TFY_BASE_URL="${TFY_BASE_URL:-${TFY_HOST:-${TFY_API_HOST:-}}}"
BASE="${TFY_BASE_URL%/}"

# --- Extract workspace FQN ---
workspace_fqn="${TFY_WORKSPACE_FQN:-}"

# Try to extract from manifest file if not in env
if [[ -z "$workspace_fqn" && -n "${manifest_file:-}" && -f "${manifest_file:-}" ]]; then
  workspace_fqn=$(grep -m1 'workspace_fqn:' "$manifest_file" 2>/dev/null | sed 's/.*workspace_fqn:[[:space:]]*//' || true)
fi

# --- Quick check: can we actually monitor? ---
if [[ -z "$TFY_BASE_URL" || -z "${TFY_API_KEY:-}" ]]; then
  echo "Deploy detected but credentials not available for auto-monitoring."
  exit 0
fi

if [[ -z "$workspace_fqn" && -z "$app_name" ]]; then
  echo "Deploy detected but could not determine app name or workspace for auto-monitoring."
  echo "Use the monitor skill to track this deployment."
  exit 0
elif [[ -z "$app_name" ]]; then
  echo "Deploy detected in workspace $workspace_fqn but could not determine app name for auto-monitoring."
  echo "Use the monitor skill to track this deployment."
  exit 0
elif [[ -z "$workspace_fqn" ]]; then
  echo "Deploy detected for $app_name but could not determine workspace for auto-monitoring."
  echo "Use the monitor skill to track this deployment."
  exit 0
fi

# --- Detect if this is an LLM deployment ---
is_llm_deploy=false
llm_pattern="vllm|tgi|llm|text-generation|triton|tensorrt"

# Check app name for LLM patterns
if echo "$app_name" | grep -qiE "$llm_pattern" 2>/dev/null; then
  is_llm_deploy=true
fi

# Check manifest for GPU resources or LLM patterns
if [[ "$is_llm_deploy" = "false" && -n "${manifest_file:-}" && -f "${manifest_file:-}" ]]; then
  if grep -qiE "(gpu|nvidia\.com/gpu|$llm_pattern)" "$manifest_file" 2>/dev/null; then
    is_llm_deploy=true
  fi
fi

# --- Record this deployment for the stop hook ---
SESSION_KEY="${CLAUDE_SESSION_ID:-${PPID:-$$}}"
STATE_DIR=$(cat "${TMPDIR:-/tmp}/tfy-plugin-state-${SESSION_KEY}" 2>/dev/null || echo "")
if [[ -n "$STATE_DIR" && -d "$STATE_DIR" ]]; then
  jq -n --arg app "$app_name" --arg workspace "$workspace_fqn" --argjson ts "$(date +%s)" \
    '{"app":$app,"workspace":$workspace,"ts":$ts}' >> "$STATE_DIR/deployments.jsonl"
fi

# --- Poll deployment status ---
echo ""
echo "Deploy command detected. Auto-monitoring: $app_name in $workspace_fqn"
if [[ "$is_llm_deploy" = "true" ]]; then
  echo "LLM deployment detected. Using extended timeout (LLM deployments typically take 10-30 minutes)."
fi
echo ""

# URL-encode via stdin to avoid shell quoting issues with special chars in names
encoded_ws=$(printf '%s' "$workspace_fqn" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))" 2>/dev/null || echo "$workspace_fqn")
encoded_app=$(printf '%s' "$app_name" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))" 2>/dev/null || echo "$app_name")

poll_count=0
if [[ "$is_llm_deploy" = "true" ]]; then
  max_polls=60  # ~20 minutes with adaptive intervals
else
  max_polls=40  # ~10 minutes with adaptive intervals
fi
start_time=$(date +%s)
final_status="UNKNOWN"
endpoint_url=""
last_status=""
model_id=""

while [[ $poll_count -lt $max_polls ]]; do
  # Adaptive interval: 15s for first 2min, 30s for 2-5min, 60s after
  elapsed=$(( $(date +%s) - start_time ))
  if [[ $elapsed -lt 120 ]]; then
    interval=15
  elif [[ $elapsed -lt 300 ]]; then
    interval=30
  else
    interval=60
  fi

  sleep "$interval"
  poll_count=$((poll_count + 1))

  # Recalculate elapsed after sleep for accurate status messages
  elapsed=$(( $(date +%s) - start_time ))

  # Fetch status
  response=$(curl -sf \
    --connect-timeout 5 --max-time 15 \
    -H "Authorization: Bearer ${TFY_API_KEY}" \
    -H "Content-Type: application/json" \
    "${BASE}/api/svc/v1/apps?workspaceFqn=${encoded_ws}&applicationName=${encoded_app}" 2>/dev/null || echo "")

  if [[ -z "$response" ]]; then
    echo "  [${elapsed}s] Could not reach API, retrying..."
    continue
  fi

  # Parse status fields
  status=$(echo "$response" | jq -r '.data[0].deployment.currentStatus.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
  transition=$(echo "$response" | jq -r '.data[0].deployment.currentStatus.transition // ""' 2>/dev/null || echo "")
  is_terminal=$(echo "$response" | jq -r '.data[0].deployment.currentStatus.state.isTerminalState // false' 2>/dev/null || echo "false")
  display=$(echo "$response" | jq -r '.data[0].deployment.currentStatus.state.display // ""' 2>/dev/null || echo "")

  final_status="$status"
  last_status="$status"

  echo "  [${elapsed}s] Status: $status${transition:+ | $transition}${display:+ | $display}"

  if [[ "$is_terminal" = "true" ]]; then
    break
  fi
done

elapsed=$(( $(date +%s) - start_time ))

# --- Report final result ---
echo ""
if [[ "$final_status" = "DEPLOY_SUCCESS" ]]; then
  # Try to extract endpoint URL
  endpoint_url=$(echo "$response" | jq -r '
    .data[0].activeComponents[0].exposedPorts[0].host // empty
  ' 2>/dev/null || echo "")

  echo "Deployment successful: $app_name ($elapsed seconds)"
  if [[ -n "$endpoint_url" ]]; then
    echo "Endpoint: https://$endpoint_url"

    # Try multiple health check paths
    health_paths=("/health" "/healthz" "/api/health" "/")
    health_ok=false
    for hpath in "${health_paths[@]}"; do
      http_code=$(curl -sf -o /dev/null -w '%{http_code}' \
        --connect-timeout 5 --max-time 10 \
        "https://${endpoint_url}${hpath}" 2>/dev/null || echo "000")

      if [[ "$http_code" =~ ^2 ]]; then
        echo "Health check: $http_code OK (path: $hpath)"
        health_ok=true
        break
      fi
    done

    if [[ "$health_ok" = "false" ]]; then
      echo "Health check: no response on /health, /healthz, /api/health, or /."
      echo "Service is deployed but not yet responding. This is normal for services with slow startup."
    fi

    # For LLM deployments, test the OpenAI-compatible API
    if [[ "$is_llm_deploy" = "true" && -n "$endpoint_url" ]]; then
      echo ""
      echo "Testing OpenAI-compatible API..."

      # Test /v1/models endpoint (should list the served model)
      models_response=$(curl -sf \
        --connect-timeout 5 --max-time 15 \
        "https://${endpoint_url}/v1/models" 2>/dev/null || echo "")

      if [[ -n "$models_response" ]]; then
        model_id=$(echo "$models_response" | jq -r '.data[0].id // empty' 2>/dev/null || echo "")
        if [[ -n "$model_id" ]]; then
          echo "OpenAI API: /v1/models responding — serving model: $model_id"

          # Test /v1/completions with a tiny request
          completion_response=$(curl -sf \
            --connect-timeout 10 --max-time 30 \
            -X POST "https://${endpoint_url}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model_id\",\"prompt\":\"Hello\",\"max_tokens\":1}" 2>/dev/null || echo "")

          if [[ -n "$completion_response" ]]; then
            has_choices=$(echo "$completion_response" | jq -r '.choices[0].text // empty' 2>/dev/null || echo "")
            if [[ -n "$has_choices" ]]; then
              echo "OpenAI API: /v1/completions responding — inference working"
            else
              echo "OpenAI API: /v1/completions returned response but no choices (model may still be loading)"
            fi
          else
            echo "OpenAI API: /v1/completions not yet responding (model may still be loading weights)"
          fi

          echo ""
          echo "To use this endpoint:"
          echo "  from openai import OpenAI"
          echo "  client = OpenAI(base_url='https://${endpoint_url}/v1', api_key='your-key')"
          echo "  response = client.completions.create(model='${model_id}', prompt='Hello', max_tokens=100)"
        else
          echo "OpenAI API: /v1/models responding but no models listed yet (still loading)"
        fi
      else
        echo "OpenAI API: /v1/models not yet responding (model may still be loading)"
      fi
    fi
  fi
elif [[ "$final_status" =~ ^(BUILD_FAILED|DEPLOY_FAILED|FAILED|CANCELLED)$ ]]; then
  echo "Deployment FAILED: $app_name ($final_status after ${elapsed}s)"
  echo "Fetching recent logs for diagnosis..."

  # Get app ID for log fetching
  app_id=$(echo "$response" | jq -r '.data[0].id // empty' 2>/dev/null || echo "")
  app_fqn=$(echo "$response" | jq -r '.data[0].fqn // empty' 2>/dev/null || echo "")

  if [[ -n "$app_id" ]]; then
    # Fetch workspace ID
    ws_response=$(curl -sf \
      --connect-timeout 5 --max-time 10 \
      -H "Authorization: Bearer ${TFY_API_KEY}" \
      "${BASE}/api/svc/v1/workspaces?fqn=${encoded_ws}" 2>/dev/null || echo "")
    ws_id=$(echo "$ws_response" | jq -r '.data[0].id // .id // empty' 2>/dev/null || echo "")

    if [[ -n "$ws_id" && -n "$app_fqn" ]]; then
      end_ts=$(date +%s)000
      start_ts=$(( end_ts - 300000 ))  # last 5 minutes
      encoded_fqn=$(printf '%s' "$app_fqn" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))" 2>/dev/null || echo "$app_fqn")
      logs=$(curl -sf \
        --connect-timeout 5 --max-time 15 \
        -H "Authorization: Bearer ${TFY_API_KEY}" \
        "${BASE}/api/svc/v1/logs/${ws_id}/download?applicationFqn=${encoded_fqn}&startTs=${start_ts}&endTs=${end_ts}" 2>/dev/null || echo "")

      if [[ -n "$logs" ]]; then
        # Filter out noise lines (healthcheck pings, empty lines) and limit output
        filtered_logs=$(echo "$logs" \
          | grep -vE '^\s*$|health.?check|GET /health|HEAD /health|GET /readyz|GET /livez' \
          || echo "$logs")

        total_lines=$(echo "$filtered_logs" | wc -l | tr -d ' ')
        echo ""
        if [[ "$total_lines" -gt 50 ]]; then
          echo "Recent logs (last 50 of $total_lines filtered lines):"
          echo "$filtered_logs" | tail -50
          echo ""
          echo "Showing last 50 lines. Use the logs skill for full log access."
        else
          echo "Recent logs (last 5 minutes):"
          echo "$filtered_logs"
        fi
      fi
    fi
  fi

  echo ""
  echo "Use the troubleshoot agent or logs skill for deeper analysis."
else
  # Timed out — provide specific guidance based on the last observed status
  echo "Monitoring timed out after ${elapsed}s. Current status: $final_status"

  if [[ "$last_status" =~ ^(BUILDING|BUILD_STARTED|IMAGE_BUILD)$ ]]; then
    echo ""
    echo "Deployment appears stuck in the BUILD phase. Suggestions:"
    echo "  - Check build logs: the image may be very large or the build is slow"
    echo "  - Verify the Dockerfile and build context for issues"
    echo "  - Look for dependency download or compilation bottlenecks"
    echo "  - Use the logs skill to inspect build output"
  elif [[ "$last_status" =~ ^(ROLLOUT_STARTED|DEPLOYING|SCALING|PENDING)$ ]]; then
    echo ""
    echo "Deployment appears stuck in the ROLLOUT phase. Suggestions:"
    echo "  - Check resource availability: cluster may lack required CPU, memory, or GPU"
    echo "  - Inspect pod events for scheduling failures or image pull errors"
    echo "  - Verify resource quotas and limits in the workspace"
    echo "  - Use 'kubectl describe pod' or the monitor skill for pod-level events"
  else
    echo "The deployment may still be in progress."
  fi

  if [[ "$is_llm_deploy" = "true" ]]; then
    echo ""
    echo "Note: LLM deployments typically take 10-30 minutes due to large model downloads and GPU initialization."
  fi

  echo "Use the monitor skill to continue tracking."
fi

# Update state file with final status
if [[ -n "$STATE_DIR" && -d "$STATE_DIR" ]]; then
  jq -n \
    --arg app "$app_name" \
    --arg workspace "$workspace_fqn" \
    --arg status "$final_status" \
    --arg endpoint "$endpoint_url" \
    --arg model "${model_id:-}" \
    --argjson ts "$(date +%s)" \
    '{"app":$app,"workspace":$workspace,"status":$status,"endpoint":$endpoint,"model":$model,"ts":$ts}' \
    > "$STATE_DIR/last-deploy.json"
fi
