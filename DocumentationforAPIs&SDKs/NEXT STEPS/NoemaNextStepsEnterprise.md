# Noema Enterprise Plan for a Role-Governed Internal Knowledge Assistant

## Current Noema baseline from the repository

Noema, as represented in the current repository, is already oriented toward an offline-first, device-resident experience, with explicit accommodation for constrained or entirely disabled networking. The iOS and iPadOS root view composition shows an onboarding flow, followed by a tab-based application shell, while the “offGrid” setting is treated as a first-class runtime mode that can disable network-dependent surfaces such as “Explore” and can also toggle a network kill switch when changed. fileciteturn19file0 fileciteturn15file0 fileciteturn22file0

The codebase also reflects a deliberate separation between local inference and externally hosted inference. The `RemoteBackend` abstraction supports multiple endpoint types, including OpenAI-compatible `/v1` endpoints and other popular provider or self-host patterns (for example OpenRouter, LM Studio, Ollama), while also supporting relay-based connectivity strategies. This is a helpful foundation for enterprise because it implies the app can evolve toward a company-hosted inference backend without redesigning the client around a single vendor. fileciteturn21file0

Tooling is similarly treated as a modular capability with explicit gating, including web retrieval, Python execution, and memory functionality, and with an offline mode that disables internet-facing tools. This architecture is valuable for enterprise, because it provides a natural bridge to “policy-driven tool access,” where a company can permit or forbid categories of tools by role, by device posture, or by network context. fileciteturn22file0

Finally, the repository contains explicit support for Apple’s “Foundation Models” framework behind conditional compilation and availability checks, with runtime guardrails modes and tool availability integration. In an enterprise design, this becomes a strong lever: the platform can select device-local models where suitable, transition to private-company inference where required, and still keep a coherent user experience. fileciteturn14file0

## Enterprise target state inspired by entity["company","Apple","consumer electronics firm"]’s Enchanté

Public reporting describes Enchanté as an internal, ChatGPT-like assistant deployed to employees, positioned as a productivity tool that can serve as a knowledge hub while being constrained to models and infrastructure approved for internal use. It is described as resembling a consumer chatbot experience while operating locally or on private servers, and it reportedly supports employee uploads (documents and media) and response feedback for iterative improvement. citeturn1search4turn0search7

These characteristics map cleanly onto the stated enterprise goal for Noema. The enterprise-grade analogue is not a generic chatbot that happens to accept corporate documents; rather, it is a governed knowledge system in which identity determines access to datasets, tools, and model backends, and in which the system can operate on-device when needed, or on private enterprise infrastructure when scale or compliance demands it. The same reporting ecosystem around Apple’s internal testing tools also highlights a broader pattern: an internal chatbot-style interface is used as a controlled environment for iterating capabilities without exposing unresolved risk to consumers. citeturn1news47turn1news45

From these sources, a reasonable, evidence-aligned enterprise target state for Noema can be framed as follows:

A company employee should see a familiar assistant interface backed by approved models, with access to internal knowledge that is both curated and permissioned, and with operational guarantees that are consistent with “private by default” deployment assumptions, including the ability to run locally or within private infrastructure. citeturn1search4turn0search7

## Enterprise architecture across app, website, Cloudflare, and Oracle

A robust enterprise version of Noema will benefit from a multi-tenant architecture in which “tenant” is the company boundary, and in which every security decision is tenant-scoped and role-mediated. This aligns with both the enterprise intent described by the user and standard security design principles that de-emphasize implicit perimeter trust in favor of explicit identity and policy checks. citeturn7search5turn2search2

### Core components and responsibilities

A practical, production-oriented topology using the allowed implementation surfaces would typically contain the following components:

**Client applications (Noema mobile, macOS, and related builds).**  
The client remains the primary user interface and should keep its offline-first posture, including the existing affordances for off-grid mode. That posture is already present in the UI shell and tool gating. fileciteturn15file0 fileciteturn22file0

**Enterprise web console and public “Enterprise plans” site.**  
The public site handles inbound interest and plan marketing, while the private console provides tenant administration (roles, datasets, SSO settings, audit exports). This is the proper locus for the “company reaches out by email, then you provision them” operational reality, because it allows a manual start while still building toward repeatable provisioning workflows.

**Edge gateway on entity["company","Cloudflare","internet services firm"] Workers.**  
Cloudflare Workers are well-suited for stateless request handling and policy enforcement at the edge, and Durable Objects can be used when a per-tenant “atom of coordination” requires consistent state, such as rate-limiting by tenant, temporary download-ticket issuance, or per-tenant key-release workflow state. Cloudflare’s own guidance emphasises that Durable Objects are appropriate for per-entity storage and strong consistency, while plain Workers are best for stateless request handling. citeturn0search0turn0search1

**Enterprise backend and update pipeline on an entity["company","Oracle","database and cloud firm"] VPS and optional OCI managed services.**  
For dataset updates and distribution, Oracle Cloud Infrastructure Object Storage provides a scalable store for versioned dataset bundles. Oracle describes Object Storage as a regional, internet-scale storage service with multiple access APIs (native REST, S3 compatibility) suited for large unstructured content distribution. citeturn0search6turn0search11

For “send dataset updates to employees,” the key design is less about pushing bytes and more about controlled distribution: generating time-bounded, auditable access to the correct dataset bundles for the correct roles. Oracle’s “pre-authenticated requests” (PARs) explicitly support granting time-bounded access to an object or bucket without distributing sign-on credentials, while warning that the URL itself is the access mechanism and must be handled carefully. citeturn1search1turn1search0turn1search5

### Enterprise request flows

A coherent end-to-end design can be expressed in four principal flows.

**Tenant provisioning flow (initially manual, designed to become automated).**  
You create a tenant record, verify the company email domain, create default roles, configure permitted model backends and datasets, and invite an initial admin. The enterprise web console is where this should live because it becomes the durable record for future audits and for later automated onboarding.

**Employee sign-in flow.**  
Employees authenticate, the system resolves their tenant and role, then the client receives a signed policy snapshot: permitted datasets, permitted models, permitted tools, and any network constraints. The policy snapshot concept is essential because it allows the app to enforce restrictions without requiring constant connectivity, while still allowing a short refresh cadence when online.

**Dataset distribution flow.**  
The client checks for dataset bundle updates. When an update is needed, it requests a download ticket from the edge gateway, and the edge gateway authorises the request by verifying the employee’s policy and then issuing a time-limited URL or a controlled token exchange that allows download from Object Storage. Oracle PARs are a viable mechanism for this, but they behave as bearer-style URLs in practice, so the design should treat them as sensitive credentials, issue them with short lifetime and narrow scope, and log issuance and use. citeturn1search1turn0search2turn1search5

**Inference flow.**  
Noema already distinguishes between local inference and remote inference backends. For enterprise, the remote path should be an organisation-controlled endpoint, either self-hosted by the company (private OpenAI-compatible endpoint) or hosted by you within an Oracle-based environment per tenant. The strategy is to retain the local-first experience while allowing role-governed escalation to larger models where policy permits. This reuses the existing remote backend abstraction rather than introducing an entirely separate enterprise inference stack in the client. fileciteturn21file0

## Identity, roles, and permissions that remain airtight under scrutiny

Airtightness requires that permissions are not merely user-interface constraints. They must be enforceable at the API layer, at dataset distribution boundaries, and, where possible, cryptographically at rest on the device. Enterprise scale also demands that identity integrates with existing corporate systems.

### Role model and entitlement vocabulary

The foundational model should be the canonical RBAC mapping of users to roles to permissions, with the option to support role hierarchies and constraints as the system matures. NIST’s RBAC model publications describe RBAC as a technology for large-scale authorisation and provide a structured model including hierarchical and constrained forms that are relevant to enterprise governance. citeturn2search2turn2search11

In Noema Enterprise terms, permissions need to cover at least:

- Dataset access (view, download, use in retrieval)  
- Model access (local model families, remote backends, specific model identifiers)  
- Tool access (web retrieval, Python, memory, internal connectors)  
- Administrative actions (role creation, dataset publishing, audit export)

Noema’s existing tool configuration and offline gating provide an implementation foothold for turning “tools” into an RBAC-governed feature set. fileciteturn22file0

### Authentication and enterprise integration

For a credible enterprise offering, authentication must support:

**OIDC SSO for modern IdPs.**  
OpenID Connect is widely used as an identity layer on top of OAuth 2.0 and supports interoperable identity claims and authentication flows. citeturn2search10turn3search10

**SAML SSO for legacy-heavy enterprises.**  
SAML 2.0 remains a common enterprise standard, and OASIS publications provide the canonical document set and errata references that enterprise security teams expect. citeturn5search0turn5search7

**SCIM provisioning for lifecycle management.**  
SCIM is designed for enterprise-to-cloud identity management, and its protocol specification describes an HTTP-based standard where authentication relies on TLS and standard schemes such as OAuth bearer tokens in practice. citeturn4search0turn3search3turn3search10turn3search0

A sensible implementation approach is to begin with domain-verified email onboarding and manual role assignment, then add SSO, and then add SCIM once the core tenant and RBAC model is stable. This sequencing minimises early complexity while creating a path to the enterprise expectation of automated joiner, mover, leaver workflows. citeturn4search0turn2search2

### Authorisation tokens and session security

At the API layer, OAuth 2.0 bearer token conventions and the relevant RFCs provide the normative guidance. OAuth 2.0 defines the framework for obtaining and using limited access, and RFC6750 details how bearer tokens are transmitted and why TLS is mandatory. citeturn3search10turn3search0

For a system distributing proprietary datasets, the operational goal is to ensure that a stolen token has sharply limited value. This implies short-lived access tokens, audience restriction, and strong server-side authorisation checks. These recommendations are aligned with the security considerations in bearer token usage documentation that emphasises the risks of bearer tokens and the necessity of transport security. citeturn3search0

### Device and secret protection on Apple platforms

Where Noema Enterprise runs on iOS and macOS, device-side secrets must be stored in a way that enterprise auditors can accept. Apple’s platform security documentation describes the Keychain as encrypted storage with Secure Enclave protections for keys, and Apple’s security guidance on Secure Enclave emphasises its isolation and role as a root for device-specific secrets. citeturn6search1turn6search2

For the highest assurance flows, device-held keys that are “this device only” and protected by Secure Enclave-backed access controls can be used to bind sensitive dataset decryption keys to a device. Apple’s Developer Documentation describes how to protect keys with the Secure Enclave and the constraints of that mechanism, which is helpful when designing device-bound encryption. citeturn6search0

## Dataset lifecycle, publishing, and updates through Oracle Object Storage

The central enterprise differentiator is not merely that employees can query internal documents; it is that access to those documents is governed, updates are reliably delivered, and the system remains useful offline.

### Dataset production pipeline

The enterprise dataset pipeline should operate as a publishable artefact system:

1. **Ingest and classify.**  
Docs are uploaded (PDF, HTML exports, Markdown, internal wiki dumps), classified by sensitivity, and assigned to a target dataset and an access policy. The classification step supports later auditing and can be linked to role constraints.

2. **Transform and index.**  
Text extraction, chunking, and embedding are performed in a deterministic build environment, producing an offline retrieval artefact compatible with the client’s expected retrieval scheme. Where embedding models are used, they must be versioned and recorded in the dataset manifest to ensure that on-device query embeddings remain compatible with the stored index.

3. **Package.**  
Each dataset build produces a signed and versioned bundle. The bundle should include a manifest, integrity hashes, and an encryption envelope.

4. **Distribute and roll out.**  
Bundles are stored in Object Storage and made available via time-bounded access mechanisms. Rollout can be staged by groups or roles, with rollback to last known good.

The enterprise need for controlled distribution aligns with the features Oracle describes: Object Storage supplies scalable storage access, while PARs supply time-bounded access without requiring employees to have OCI credentials, albeit with strong warnings that the URL itself is the access mechanism and must be carefully managed. citeturn0search6turn1search1turn1search5

### Dataset distribution and update mechanics

A workable and auditable scheme using the specified infrastructure surfaces is:

- The dataset bundle lives in an OCI bucket scoped per tenant, with object versioning or explicit semantic versioning in the object key naming convention.
- The Noema Enterprise edge gateway mediates downloads and issues short-lived download authorisations after verifying the current policy snapshot.
- The download authorisation can be implemented as:
  - A freshly created PAR with narrow scope and short expiration, or  
  - A pre-signed URL using the S3-compatibility API pattern, which Oracle explicitly maps conceptually to PARs and warns should be treated as bearer-token-like URLs. citeturn1search1turn0search2turn1search0

Oracle’s documentation states that PAR URLs are displayed only at creation time and are not retrievable later, which means your system should store the generated URL securely if PARs are used, or generate PARs on demand rather than creating long-lived “static” PARs. citeturn1search0turn1search2

To preserve the offline goal, the client should store downloaded dataset bundles locally and apply them transactionally, keeping the previous version available until the new version is verified and activated. The existing Noema posture around off-grid mode and explicit gating suggests that the enterprise update mechanism should respect a company policy that can prohibit networking, while still allowing periodic controlled sync windows where policy permits. fileciteturn15file0 fileciteturn22file0

### Cryptographic and policy enforcement for “airtight” separation

A security-sensitive enterprise design benefits from three concentric controls:

**Server-side authorisation.**  
Every dataset download ticket is issued based on tenant-scoped identity and role entitlement, and the backend should enforce object-level access control for dataset identifiers, aligning with OWASP’s emphasis on broken object level authorisation as a primary API risk. citeturn2search1turn2search0

**Encrypted dataset bundles.**  
The bundle contents should be encrypted at rest on the device. Keys should be tenant-scoped, rotated, and optionally device-bound using platform key stores. Apple’s keychain and Secure Enclave documentation provides the necessary references for explaining and justifying device-bound secret storage. citeturn6search1turn6search0turn6search2

**On-device policy enforcement.**  
Even though the server is authoritative, the client should enforce least privilege in UI and tool gating, including disallowing model backends or tools that are not permitted for the role. Noema’s existing tool gating is a strong starting point for implementing “policy-driven tool availability.” fileciteturn22file0

## UI/UX and enterprise dashboards built around governed access

Noema’s existing app structure, including onboarding followed by a tab-based shell, provides a natural insertion point for enterprise flows: the enterprise experience should be presented as an extension of onboarding and settings, not as a parallel application. fileciteturn19file0turn15file0

### Employee experience

An enterprise employee flow should feel uncomplicated while being meaningfully controlled:

- **Join and authenticate.**  
The employee enters a work email, the system resolves tenant by domain, and the employee completes SSO if configured. If the tenant uses SCIM, the employee’s role resolves automatically from group membership. citeturn4search0turn2search10turn5search0

- **Policy snapshot and dataset readiness.**  
Upon sign-in, the app fetches a signed policy snapshot indicating which datasets are available and whether the device should remain off-grid by policy. This mirrors Noema’s existing emphasis on toggling network access and tool availability, but shifts the source of truth from local user defaults to tenant policy. fileciteturn22file0

- **Chat with transparent grounding.**  
When responses are grounded in internal datasets, the UI should show sources and dataset names, and should provide a way for employees to report incorrect references. This aligns with the public description of Enchanté allowing employee feedback for improvement. citeturn1search4turn0search7

- **Model selection that is role-limited.**  
The UI may retain Noema’s rich model capabilities, but the available list should be filtered by role, and the app should clearly indicate whether a request is executed locally, on a company server, or via another approved private endpoint. Noema’s remote backend abstractions make it feasible to present “approved enterprise backends” as preconfigured endpoints rather than user-entered URLs. fileciteturn21file0

### Admin console experience

Enterprise administrators require a console that is both empowering and restrained:

- **Tenant setup.**  
Domain verification, SSO configuration, SCIM endpoint configuration (if used), and baseline security posture (for example “no internet tools allowed”). citeturn4search0turn2search10turn5search0

- **Roles and access policy.**  
Role hierarchy, dataset entitlements, model entitlements, tool entitlements, and restrictions on remote inference. This should align with a formal RBAC model to satisfy security review. citeturn2search2turn2search11

- **Datasets.**  
Upload and ingestion, build status, approvals, publish actions, staged rollout, and rollback. Artifact-level logging is critical for audit.

- **Audit and risk signals.**  
At minimum: sign-in events, policy snapshot issuance, dataset download ticket issuance, dataset bundle download events, and administrative changes. Oracle notes that PAR accesses are logged in audit or service logs depending on bucket versus object scope, which supports the auditability requirement if PARs are employed. citeturn1search5turn1search1

## Security, operational readiness, and phased roadmap

### Security posture and standards alignment

An enterprise assistant is evaluated as much on its security and governance as on its UX. The design should explicitly address:

- **Zero trust assumptions.**  
NIST’s SP 800-207 describes zero trust as shifting defence focus from network perimeters to individual resources, and emphasises discrete authentication and authorisation before sessions are established. The Noema Enterprise design should treat every dataset, model backend, and administrative action as a protected resource requiring explicit policy checks. citeturn7search5turn7search0

- **API risk mitigation.**  
OWASP’s API Security Top 10 lists broken object level authorisation and broken function level authorisation among the dominant API risks, which is directly relevant when datasets and models are accessed by identifier and when admin capabilities exist. These risks should be used as a checklist for endpoint design and authorization review. citeturn2search1turn2search0

- **Information security management.**  
ISO/IEC 27001 defines requirements for an information security management system and is frequently used as a benchmark for enterprise vendors. Even if certification is not an immediate goal, the control themes (risk-based governance, continual improvement) provide a framework for operational maturity planning. citeturn7search9

- **AI governance and risk management.**  
NIST’s AI Risk Management Framework is explicitly intended to help organisations manage AI risks and promote trustworthy deployment, and its generative AI profile offers further guidance focused on generative systems. This supports an enterprise narrative that Noema is not only secure, but governed with attention to model risk, data handling, and evaluation practices. citeturn7search2turn7search13

### Phased roadmap grounded in the current codebase

A credible delivery plan should respect what Noema already has, while sequencing enterprise complexity in a way that avoids fragile early overbuild.

**Foundation phase: enterprise substrate and policy enforcement**  
Deliver tenant registry, policy snapshot issuing, role mapping by email domain, and a minimal admin console. Integrate policy into existing client gating for tools and network mode, building on Noema’s current tool configuration patterns. fileciteturn22file0

**Core enterprise phase: datasets as signed, versioned artefacts with secure distribution**  
Implement a dataset ingestion and packaging pipeline, publish bundles to OCI Object Storage, and deliver time-bounded downloads mediated by the edge gateway, using PARs or equivalent short-lived authorisations with careful handling as Oracle recommends. citeturn1search1turn1search0turn1search5

**Enterprise integration phase: SSO and SCIM**  
Add OIDC and SAML identity integration, then SCIM provisioning for automated role assignment and lifecycle. Ensure token handling follows OAuth 2.0 and bearer token transport guidance, including strict TLS, short token lifetimes, and structured auditing. citeturn2search10turn5search0turn4search0turn3search10turn3search0

**Maturity phase: private inference backends and governance**  
Leverage Noema’s remote backend architecture to support preconfigured, tenant-private inference backends, with per-role model policies and auditable inference mode selection. Extend governance using AI RMF-aligned evaluation and feedback mechanisms, reflecting the patterns described for internal assistants such as Enchanté where employee feedback informs iteration. fileciteturn21file0 citeturn1search4turn7search2