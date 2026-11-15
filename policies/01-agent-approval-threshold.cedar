// No single agent may auto-approve a payment above the routine-amount
// threshold. Above $5,000, only a human (approval-authority tier >= 2,
// i.e. controller or cfo-approver) may approve - never an agent acting
// alone, regardless of its confidence score.
forbid (
    principal is FourEyes::Agent,
    action == FourEyes::Action::"ApprovePayment",
    resource is FourEyes::Payment
)
when {
    resource.amount > 5000
};

permit (
    principal is FourEyes::User,
    action == FourEyes::Action::"ApprovePayment",
    resource is FourEyes::Payment
)
when {
    resource.amount > 5000 &&
    principal.approvalAuthorityTier >= 2
};

// Agents may auto-approve routine amounts at or below the threshold.
permit (
    principal is FourEyes::Agent,
    action == FourEyes::Action::"ApprovePayment",
    resource is FourEyes::Payment
)
when {
    resource.amount <= 5000
};
