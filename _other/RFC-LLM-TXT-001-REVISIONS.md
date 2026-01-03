# RFC-LLM-TXT-001 Revision History and Decision Audit

```
Document ID: RFC-LLM-TXT-001-REVISIONS
Status: Living Document
Maintainer: LLM.TXT Working Group
Created: January 2026
Last Updated: January 2026
```

---

## Purpose

This document provides an auditable record of all decisions, discussions, and revisions to RFC-LLM-TXT-001. It serves as the governance record for the LLM.TXT specification, ensuring transparency and traceability of design decisions.

---

## Version History

| Version | Date | Status | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-01-01 | Superseded | Initial specification release |
| 1.1.0 | 2026-01-01 | Current | Topic-oriented revision based on multi-party consensus |

---

## Revision 1.1.0: Topic-Oriented Knowledge Blocks

### Revision Metadata

```
REVISION_ID :: REV-2026-001
VERSION_FROM :: 1.0.0
VERSION_TO :: 1.1.0
REVISION_DATE :: 2026-01-01
REVISION_TYPE :: Major philosophical revision
CONSENSUS_LEVEL :: Multi-party agreement
PARTICIPANTS :: Human maintainer; Claude (Anthropic); Gemini (Google)
```

---

### Discussion Summary

#### Participant 1: Gemini (Google) - External Review

**Review Type:** Critical analysis of v1.0.0 specification

**Key Points Raised:**

| Point ID | Category | Concern | Validity Assessment |
|----------|----------|---------|---------------------|
| G-001 | Maintenance | "Drift Problem" - documentation becomes stale | VALID - Accepted |
| G-002 | Efficiency | Token inefficiency due to verbose prefixes | PARTIALLY VALID - Addressed |
| G-003 | Structure | 80-char separators unnecessarily rigid | VALID - Relaxed to RECOMMENDED |
| G-004 | Search | Grepability vs semantic search false dichotomy | INVALID - Formats are complementary |
| G-005 | Linking | Need for source code deep linking | VALID - Accepted |
| G-006 | Sections | Auto vs Manual section distinction needed | VALID - Accepted |
| G-007 | Syntax | Compressed syntax proposal (F:: instead of FUNC::) | REJECTED - Reduces clarity |
| G-008 | Files | Virtual FILE_TREE instead of manifest | REJECTED - Loses semantic value |

**Accepted Proposals:**
- COMMIT_HASH and GENERATED_AT headers
- SECTION_TYPE :: AUTO | MANUAL distinction  
- LOC :: filepath:line-range prefix
- Relaxed separator requirements

**Rejected Proposals:**
- Compressed prefix syntax
- Removal of FILE_MANIFEST
- Markdown headers instead of delimiters

#### Participant 2: Human Maintainer - Intervention

**Intervention Type:** Fundamental philosophical correction

**Key Insight:**

> "Lines should be single complete collective understanding... greps should return large amounts of information, tend to over-collect on topics. Fundamentally we are trying to encourage topic modeling in the spec."

**Analysis:**

The human correctly identified that v1.0.0 optimized for the wrong atomic unit:

| v1.0.0 Approach | Problem |
|-----------------|---------|
| Atomic facts per line | `FUNC :: login()` alone has zero actionable value |
| Precise grep returns | Returns fragments requiring mental assembly |
| Fact-type grouping | FUNC_PARAM lines lack function context |

**Proposed Correction:**

| v1.1.0 Approach | Benefit |
|-----------------|---------|
| Atomic understanding per line | Each line is complete and actionable |
| Over-collection encouraged | Related information clusters together |
| Topic-oriented grouping | DETAIL:login groups all login information |

#### Participant 3: Claude (Anthropic) - Synthesis

**Role:** Synthesize multi-party input into coherent revision

**Synthesis Approach:**
1. Accept valid critiques from Gemini
2. Implement human's topic-oriented philosophy
3. Maintain backward compatibility where possible
4. Preserve core grepability principle

---

### Decisions Made

#### Decision D-001: Adopt Topic-Oriented Architecture

```
DECISION_ID :: D-001
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Architectural
PARTICIPANTS :: Human, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Before (v1.0.0):**
```
FUNC :: login()
FUNC_FILE :: ./src/auth.py
FUNC_SIGNATURE :: login(username: str, password: str) -> SessionToken
FUNC_PURPOSE :: Validate user credentials
FUNC_PARAM :: username (str) - user's login identifier
FUNC_PARAM :: password (str) - user's password
FUNC_RETURNS :: SessionToken on success
```

**After (v1.1.0):**
```
FUNC :: login(username:str, password:str) -> SessionToken | Validate credentials and create session | LOC:./src/auth.py:45-67 | RAISES:InvalidCredentials | PURE:no
DETAIL:login :: PARAM username - user's login identifier; must be valid email format
DETAIL:login :: PARAM password - plaintext password; hashed via bcrypt before comparison
DETAIL:login :: RETURNS SessionToken - JWT with 24hr expiry; contains user_id and permissions
DETAIL:login :: FLOW validate_format -> check_exists -> verify_hash -> create_session -> return
```

**Rationale:** Each grep now returns complete, actionable understanding. No orphaned fragments.

---

#### Decision D-002: Add Integrity Headers

```
DECISION_ID :: D-002
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Format addition
PARTICIPANTS :: Gemini, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Addition:**
```
# COMMIT_HASH :: <git_short_hash>
# GENERATED_AT :: <ISO8601_timestamp>
# GENERATOR :: <tool_name> | manual
```

**Rationale:** Addresses the "drift problem" by allowing agents to detect stale documentation.

---

#### Decision D-003: Add Section Type Markers

```
DECISION_ID :: D-003
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Format addition
PARTICIPANTS :: Gemini, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Addition:**
```
SECTION_TYPE :: AUTO | MANUAL | HYBRID
```

**Rationale:** Allows AI agents to weight trust appropriately - facts from AUTO, intent from MANUAL.

---

#### Decision D-004: Add LOC Prefix for Deep Linking

```
DECISION_ID :: D-004
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Prefix addition
PARTICIPANTS :: Gemini, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Addition:**
```
LOC :: filepath:line_start-line_end
```

**Rationale:** Enables agents to jump directly to source when llm.txt is insufficient.

---

#### Decision D-005: Add TOPIC Grouping Markers

```
DECISION_ID :: D-005
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Format addition
PARTICIPANTS :: Human, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Addition:**
```
TOPIC :: TOPIC_NAME
TOPIC_DESCRIPTION :: What this topic covers
TOPIC_FILES :: Files involved
TOPIC_RELATED :: Related topics
```

**Rationale:** Enables topic-level navigation and retrieval.

---

#### Decision D-006: Add DETAIL Block Pattern

```
DECISION_ID :: D-006
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Format addition
PARTICIPANTS :: Human, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Addition:**
```
DETAIL:parent_topic :: CATEGORY content
```

Categories: PARAM, RETURNS, RAISES, FLOW, EDGE, SECURITY, EXAMPLE, NOTE

**Rationale:** Associates detailed information with parent topic for contextual retrieval.

---

#### Decision D-007: Add Inline Segment Delimiter

```
DECISION_ID :: D-007
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Delimiter addition
PARTICIPANTS :: Human, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Addition:**
```
| (pipe) - separates segments within a line
```

**Usage:**
```
FUNC :: signature | purpose | location | behaviors
```

**Rationale:** Enables complete understanding in a single line while maintaining parseability.

---

#### Decision D-008: Relax Separator Requirements

```
DECISION_ID :: D-008
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Requirement relaxation
PARTICIPANTS :: Gemini, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Change:** 80-character separator changed from MUST to SHOULD

**Rationale:** The specific length is less important than consistency. Reduces barriers to adoption.

---

#### Decision D-009: Reject Compressed Prefix Syntax

```
DECISION_ID :: D-009
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Proposal rejection
PARTICIPANTS :: Gemini (proposer), Claude, Human
CONSENSUS :: Majority reject
STATUS :: Rejected
```

**Proposal:** Replace `FUNC_PARAM ::` with `FP ::`

**Rejection Rationale:**
1. Reduces self-documentation (FP requires lookup)
2. Marginal token savings (~8 chars)
3. Introduces cognitive overhead
4. grep "FUNC_PARAM" is clearer than grep "FP"

---

#### Decision D-010: Reject Virtual FILE_TREE

```
DECISION_ID :: D-010
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Proposal rejection
PARTICIPANTS :: Gemini (proposer), Claude, Human
CONSENSUS :: Unanimous reject
STATUS :: Rejected
```

**Proposal:** Replace FILE_MANIFEST with `tree` command output

**Rejection Rationale:**
1. Tree shows existence, not purpose
2. Loses semantic information (FILE_PURPOSE, FILE_CONTAINS)
3. Agent must open files to understand them
4. Violates "complete understanding" principle

---

#### Decision D-011: Rename Core Principle

```
DECISION_ID :: D-011
DECISION_DATE :: 2026-01-01
DECISION_TYPE :: Terminology change
PARTICIPANTS :: Human, Claude
CONSENSUS :: Unanimous
STATUS :: Implemented in v1.1.0
```

**Change:** "Line Atomicity" renamed to "Understanding Atomicity"

**Before:** "Every line must be a complete, self-contained unit of knowledge"
**After:** "Each greppable line MUST provide complete understanding of its topic"

**Rationale:** Emphasizes that the atomic unit is understanding, not facts.

---

### Revision Plan Execution

#### Phase 1: Header Updates

| Task | Status | Description |
|------|--------|-------------|
| T-001 | ✅ Complete | Update version to 1.1.0 |
| T-002 | ✅ Complete | Add revision date |
| T-003 | ✅ Complete | Update status to "Revised Standard" |

#### Phase 2: Principle Updates

| Task | Status | Description |
|------|--------|-------------|
| T-004 | ✅ Complete | Rename G1 to "Understanding Atomicity" |
| T-005 | ✅ Complete | Add "Over-Collection" as new principle |
| T-006 | ✅ Complete | Add "Topic Orientation" as new principle |

#### Phase 3: Format Additions

| Task | Status | Description |
|------|--------|-------------|
| T-007 | ✅ Complete | Add integrity header specification |
| T-008 | ✅ Complete | Add SECTION_TYPE marker |
| T-009 | ✅ Complete | Add LOC prefix to registry |
| T-010 | ✅ Complete | Add TOPIC marker specification |
| T-011 | ✅ Complete | Add DETAIL block pattern |
| T-012 | ✅ Complete | Add pipe delimiter specification |

#### Phase 4: Section Updates

| Task | Status | Description |
|------|--------|-------------|
| T-013 | ✅ Complete | Update FUNCTION_REFERENCE specification |
| T-014 | ✅ Complete | Add examples with new format |
| T-015 | ✅ Complete | Update conformance checklists |

#### Phase 5: Requirement Adjustments

| Task | Status | Description |
|------|--------|-------------|
| T-016 | ✅ Complete | Relax separator to SHOULD |
| T-017 | ✅ Complete | Update validation rules |

---

### Backward Compatibility

#### Compatibility Assessment

| v1.0.0 Feature | v1.1.0 Status | Migration Path |
|----------------|---------------|----------------|
| Basic prefixes (FILE, FUNC, etc.) | Preserved | None required |
| :: delimiter | Preserved | None required |
| >> hierarchy delimiter | Preserved | None required |
| -> flow delimiter | Preserved | None required |
| Section headers | Preserved | None required |
| 80-char separators | Now SHOULD (was MUST) | Optional update |
| Atomic fact lines | Deprecated | Migrate to summary lines |
| FUNC_PARAM scattered | Deprecated | Migrate to DETAIL blocks |

#### Migration Guidance

**v1.0.0 Document:**
```
FUNC :: login()
FUNC_FILE :: ./src/auth.py
FUNC_PURPOSE :: Validate credentials
FUNC_PARAM :: username (str)
FUNC_PARAM :: password (str)
```

**v1.1.0 Migration:**
```
FUNC :: login(username:str, password:str) -> SessionToken | Validate credentials | LOC:./src/auth.py:45-67
DETAIL:login :: PARAM username (str) - user identifier
DETAIL:login :: PARAM password (str) - user password
```

---

### Open Issues

| Issue ID | Status | Description | Assignee |
|----------|--------|-------------|----------|
| I-001 | Open | Define maximum recommended line length for summary lines | Working Group |
| I-002 | Open | Specify behavior when grep returns >100 lines | Working Group |
| I-003 | Open | Consider YAML/TOML alternative for structured segments | Future revision |

---

### Governance Notes

#### Decision-Making Process

1. Proposals may be submitted by any participant
2. Discussion continues until consensus or clear majority
3. Decisions are recorded with rationale
4. Rejections include explanation
5. All decisions are auditable via this document

#### Consensus Definition

- **Unanimous:** All participants agree
- **Majority:** >50% of participants agree
- **Consensus:** No strong objections after discussion

#### Amendment Process

1. Propose change with rationale
2. Record in revision document
3. Discuss with participants
4. Record decision
5. Implement if accepted
6. Update version number

---

### Document Signatures

```
REVISION_APPROVED_BY :: Working Group Consensus
APPROVAL_DATE :: 2026-01-01
NEXT_REVIEW_DATE :: 2026-04-01
```

---

## Future Revision Considerations

### Under Consideration for v1.2.0

| Proposal | Source | Status |
|----------|--------|--------|
| Binary format alternative | Community | Under discussion |
| Schema validation tooling | Community | Under discussion |
| Multi-file llm.txt for large repos | Gemini review | Under discussion |
| Embedding optimization markers | Community | Under discussion |

---

*This document is maintained alongside RFC-LLM-TXT-001 and serves as the authoritative record of specification governance.*
