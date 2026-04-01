---
name: truefoundry-agents
description: Manages TrueFoundry AI agents. List, create, update, and delete agents that are backed by ChatPrompts or external A2A agent cards.
license: MIT
compatibility: Requires Bash, curl, and access to a TrueFoundry instance
allowed-tools: Bash(*/tfy-api.sh *)
---

> Routing note: For ambiguous user intents, use the shared clarification templates in [references/intent-clarification.md](references/intent-clarification.md).

<objective>

# AI Agents

Manage TrueFoundry AI agents. Agents can be prompt-based (backed by a ChatPrompt version) or hosted A2A agents (external agents via the A2A protocol).

## When to Use

- User wants to list, create, update, or delete AI agents
- User wants to register an external A2A agent
- User wants to connect a ChatPrompt to an agent
- User asks about agent versions or agent applications

## When NOT to Use

- User wants to create a ChatPrompt -> use the prompts API directly
- User wants to deploy a service -> prefer `deploy` skill
- User wants to manage MCP servers -> see `manifest-schema.md` MCP Server sections

</objective>

<instructions>

## Execution Priority

For agent operations, use MCP tool calls first when available:
- `tfy_agents_list`
- `tfy_agents_create`
- `tfy_agents_delete`

If tool calls are unavailable, fall back to direct API via `tfy-api.sh`.

When using direct API, set `TFY_API_SH` to the full path of this skill's `scripts/tfy-api.sh`. See `references/tfy-api-setup.md` for paths per agent.

## List Agents

### Via Tool Call

```
tfy_agents_list()
tfy_agents_list(filters={"name": "support-agent"})
tfy_agents_list(filters={"workspace_fqn": "cluster:workspace"})
```

### Via Direct API

```bash
TFY_API_SH=~/.claude/skills/truefoundry-agents/scripts/tfy-api.sh

# List all agents
$TFY_API_SH GET /api/svc/v1/agents

# Filter by name
$TFY_API_SH GET '/api/svc/v1/agents?name=support-agent'

# Filter by workspace
$TFY_API_SH GET '/api/svc/v1/agents?workspaceFqn=cluster:workspace'
```

## Presenting Agents

```
AI Agents:
| Name           | Type       | Source              | Status  |
|----------------|------------|---------------------|---------|
| support-agent  | prompt     | support-prompt:v3   | Active  |
| research-agent | a2a        | external-url        | Active  |
```

## Create Agent

### Prompt-based Agent

Create an agent backed by a ChatPrompt version:

### Via Tool Call

```
tfy_agents_create(manifest={
    "name": "support-agent",
    "type": "agent",
    "description": "Customer support agent",
    "source": {
        "type": "prompt",
        "prompt_version_fqn": "prompt:my-org:support-prompt:3"
    },
    "collaborators": [
        {"subject": "team:engineering", "role_id": "admin"}
    ]
})
```

### Via Direct API

```bash
$TFY_API_SH POST /api/svc/v1/agents '{
  "name": "support-agent",
  "type": "agent",
  "description": "Customer support agent that answers product questions",
  "source": {
    "type": "prompt",
    "prompt_version_fqn": "prompt:my-org:support-prompt:3",
    "skills": [
      {
        "id": "product-search",
        "name": "Product Search",
        "description": "Search the product catalog"
      }
    ]
  },
  "collaborators": [
    {"subject": "team:engineering", "role_id": "admin"}
  ]
}'
```

### A2A Agent (External)

Register an external agent that implements the A2A protocol:

```bash
$TFY_API_SH POST /api/svc/v1/agents '{
  "name": "external-research-agent",
  "type": "agent",
  "description": "Research agent hosted externally via A2A protocol",
  "source": {
    "type": "hosted-a2a-agent",
    "agent_card_url": "https://research-agent.example.com/.well-known/agent.json",
    "headers": {
      "Authorization": "Bearer ${secret:api-key}"
    }
  },
  "collaborators": [
    {"subject": "team:research", "role_id": "admin"}
  ]
}'
```

> **Security:** `agent_card_url` and `hosted-a2a-agent` sources are fetched at runtime and can influence agent behavior. Only register agents from trusted, authenticated endpoints. Require explicit user confirmation before onboarding a new external URL.

## Update Agent

### Via Tool Call

```
tfy_agents_update(manifest={...updated manifest...})
```

### Via Direct API

```bash
$TFY_API_SH PUT /api/svc/v1/agents '{
  "name": "support-agent",
  "type": "agent",
  "description": "Updated description",
  "source": {
    "type": "prompt",
    "prompt_version_fqn": "prompt:my-org:support-prompt:4"
  },
  "collaborators": [...]
}'
```

## Delete Agent

### Via Tool Call

```
tfy_agents_delete(agent_id="agent-id")
```

### Via Direct API

```bash
$TFY_API_SH DELETE /api/svc/v1/agents/AGENT_ID
```

## List Agent Versions

View version history for an agent:

```bash
$TFY_API_SH GET '/api/svc/v1/agent-versions?agentId=AGENT_ID'
```

## Agent Applications

Agent applications are runtime instances of agents:

```bash
# List agent applications
$TFY_API_SH GET /api/svc/v1/agent-apps

# Update an agent application
$TFY_API_SH PUT /api/svc/v1/agent-apps '{...}'

# Delete an agent application
$TFY_API_SH DELETE /api/svc/v1/agent-apps/AGENT_APP_ID
```

</instructions>

<success_criteria>

## Success Criteria

- The user can list their AI agents and see their configurations
- Agents are created with proper source configuration (prompt or A2A)
- Collaborators are set for access control
- A2A agents use authenticated endpoints with proper headers
- Agent versions are tracked and can be queried

</success_criteria>

<references>

## Composability

- **Create prompts first**: Use the prompts API to create ChatPrompts before creating prompt-based agents
- **After creating agent**: Test via Agent Chat UI in TrueFoundry dashboard
- **For access control**: Use `access-control` skill to manage team permissions
- **For secrets in headers**: Use `secrets` skill to create secret groups for A2A auth

</references>

<troubleshooting>

## Error Handling

### Agent Not Found
```
Agent ID not found. List agents first to find the correct ID.
```

### Invalid Prompt Version FQN
```
The prompt_version_fqn is invalid. Format: "prompt:tenant:prompt-name:version"
```

### A2A Agent Card Unreachable
```
Cannot fetch agent card from URL. Check:
- URL is accessible
- Headers are correct
- Network allows outbound connections
```

### Permission Denied
```
Cannot access this agent. Check your API key permissions and collaborator settings.
```

</troubleshooting>
