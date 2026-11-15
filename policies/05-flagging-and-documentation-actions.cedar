// FlagForReview, RequestAdditionalDocumentation, and UpdateVendorRecord had
// no Cedar rule at all until this file - the schema declared the actions
// and the capability manifests (foureyes-backend/app/capability-manifests/
// *.json) enforced them in code, but Cedar itself default-denied every
// call, silently, since project inception. Found by testing the real
// authorize() call risk_scoring.py makes, not by code review. These rules
// mirror the capability manifests exactly - Cedar and the manifests must
// agree, since either one alone denying an action is enough to block it.
permit (
    principal == FourEyes::Agent::"risk-scoring",
    action == FourEyes::Action::"FlagForReview",
    resource is FourEyes::Payment
);

permit (
    principal == FourEyes::Agent::"approval",
    action == FourEyes::Action::"FlagForReview",
    resource is FourEyes::Payment
);

permit (
    principal == FourEyes::Agent::"payment-execution",
    action == FourEyes::Action::"FlagForReview",
    resource is FourEyes::Payment
);

permit (
    principal == FourEyes::Agent::"extraction",
    action == FourEyes::Action::"RequestAdditionalDocumentation",
    resource is FourEyes::Payment
);

permit (
    principal == FourEyes::Agent::"risk-scoring",
    action == FourEyes::Action::"RequestAdditionalDocumentation",
    resource is FourEyes::Payment
);

permit (
    principal == FourEyes::Agent::"approval",
    action == FourEyes::Action::"RequestAdditionalDocumentation",
    resource is FourEyes::Payment
);

permit (
    principal == FourEyes::Agent::"approval",
    action == FourEyes::Action::"UpdateVendorRecord",
    resource is FourEyes::Payment
);
