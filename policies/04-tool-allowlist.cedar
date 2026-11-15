// Explicit per-agent tool allowlist, checked via policy-service on every
// InvokeTool request (e.g. foureyes-sandbox-runner's own authorization
// check before spawning a sandbox) - default deny, no open discovery.
// Each permit names exactly the tools that agent's role needs; nothing else.
// Standalone Cedar logic - not related to the removed mcp_trust_proxy
// check (see INSTRUCTIONS.md 5.5), which was a separate Python-level gate.
permit (
    principal == FourEyes::Agent::"extraction",
    action == FourEyes::Action::"InvokeTool",
    resource
)
when {
    ["request-additional-documentation", "sandbox-ocr"].contains(resource.name)
};

permit (
    principal == FourEyes::Agent::"risk-scoring",
    action == FourEyes::Action::"InvokeTool",
    resource
)
when {
    ["flag-for-review", "request-additional-documentation"].contains(resource.name)
};

permit (
    principal == FourEyes::Agent::"approval",
    action == FourEyes::Action::"InvokeTool",
    resource
)
when {
    ["flag-for-review", "request-additional-documentation", "update-vendor-record"].contains(resource.name)
};

permit (
    principal == FourEyes::Agent::"payment-execution",
    action == FourEyes::Action::"InvokeTool",
    resource
)
when {
    ["create-ledger-entry", "flag-for-review"].contains(resource.name)
};
