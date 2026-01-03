# RFC-LLM-TXT-001: LLM.TXT Repository Documentation Format Specification

```
Request for Comments: LLM-TXT-001
Category: Standards Track
Status: Revised Standard
Version: 1.1.0
Supersedes: 1.0.0
Date: January 2026
Revised: January 2026
Author: LLM.TXT Working Group
Contributors: Human Maintainer, Claude (Anthropic), Gemini (Google)
Revision History: See RFC-LLM-TXT-001-REVISIONS.md
```

## Status of This Memo

This document specifies a revised standard format for repository documentation optimized for consumption by Large Language Models (LLMs) and AI agent systems. This revision (1.1.0) incorporates multi-party consensus feedback and introduces a topic-oriented architecture.

**Key Changes from v1.0.0:**
- Topic-oriented knowledge blocks (complete understanding per line)
- DETAIL block pattern for associated information
- Integrity headers for staleness detection
- Section type markers (AUTO/MANUAL)
- Over-collection as explicit design goal
- Relaxed formatting requirements

## Copyright Notice

This document is released into the public domain. No rights reserved.

---

## Table of Contents

1. [Abstract](#1-abstract)
2. [Introduction](#2-introduction)
3. [Terminology](#3-terminology)
4. [Design Goals](#4-design-goals)
5. [Format Specification](#5-format-specification)
6. [Section Specifications](#6-section-specifications)
7. [Delimiter Grammar](#7-delimiter-grammar)
8. [Prefix Registry](#8-prefix-registry)
9. [Topic-Oriented Patterns](#9-topic-oriented-patterns)
10. [Conformance Levels](#10-conformance-levels)
11. [Validation Rules](#11-validation-rules)
12. [Security Considerations](#12-security-considerations)
13. [Implementation Guidance](#13-implementation-guidance)
14. [Examples](#14-examples)
15. [Migration from v1.0.0](#15-migration-from-v100)
16. [References](#16-references)
17. [Appendix A: Complete Section Reference](#appendix-a-complete-section-reference)
18. [Appendix B: Prefix Quick Reference](#appendix-b-prefix-quick-reference)
19. [Appendix C: Conformance Checklist](#appendix-c-conformance-checklist)

---

## 1. Abstract

This document defines LLM.TXT, a standardized format for repository documentation designed specifically for machine comprehension by Large Language Models and AI agent systems.

**v1.1.0 Key Innovation:** Topic-Oriented Knowledge Blocks

Unlike traditional documentation that fragments information across many lines, LLM.TXT v1.1.0 ensures that each retrievable unit provides **complete understanding** of its topic. When an AI agent queries for "login", it receives everything needed to understand login - not fragments requiring assembly.

The format prioritizes:
- **Understanding Atomicity:** Each line provides complete, actionable knowledge
- **Over-Collection:** Grep returns comprehensive topic information
- **Topic Modeling:** Related information clusters together
- **Zero-Ambiguity:** Explicit types, defaults, constraints, and behaviors

---

## 2. Introduction

### 2.1 Problem Statement

AI systems interacting with codebases face significant challenges:

1. **Fragmented Information:** Facts scattered across multiple lines lose context
2. **Assembly Required:** Agents must combine fragments to form understanding
3. **Orphaned Data:** Individual lines lack meaning without neighbors
4. **Precise Returns:** Grep returns exactly what's asked for, missing related context

### 2.2 The Topic-Oriented Solution

LLM.TXT v1.1.0 introduces topic-oriented knowledge blocks:

**Old Approach (v1.0.0 - Fact-Oriented):**
```
FUNC :: login()
FUNC_FILE :: ./src/auth.py
FUNC_PURPOSE :: Validate credentials
FUNC_PARAM :: username (str)
FUNC_PARAM :: password (str)
```
*Problem: `FUNC :: login()` alone is meaningless. Agent must read 5+ lines.*

**New Approach (v1.1.0 - Topic-Oriented):**
```
FUNC :: login(username:str, password:str) -> SessionToken | Validate credentials and create session | LOC:./src/auth.py:45-67 | RAISES:InvalidCredentials | PURE:no
DETAIL:login :: PARAM username - user's login identifier; must be valid email
DETAIL:login :: PARAM password - plaintext; hashed via bcrypt before comparison
DETAIL:login :: FLOW validate -> verify -> create_session -> return_token
```
*Solution: First line provides complete understanding. DETAIL lines add depth.*

### 2.3 Scope

This specification covers:
- File format and structure
- Topic-oriented knowledge patterns
- Delimiter and prefix conventions
- Conformance levels and validation
- Migration from v1.0.0

### 2.4 Document Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

---

## 3. Terminology

### 3.1 Core Definitions

**Understanding Unit:** A retrievable line that provides complete, actionable knowledge about a topic. The fundamental building block of LLM.TXT v1.1.0.

**Summary Line:** A dense line containing complete topic understanding using inline segment delimiters. Designed for single-query comprehension.

**Detail Block:** A group of DETAIL lines associated with a parent topic, providing in-depth information while maintaining topic context.

**Topic Marker:** A TOPIC line that groups related understanding units for navigation and bulk retrieval.

**Over-Collection:** The design principle that grep queries should return more information than minimally requested, ensuring complete topic coverage.

### 3.2 Inherited Definitions (from v1.0.0)

**LLM.TXT:** A plain text file named `llm.txt` in repository root.

**Section:** A logical grouping bounded by section headers.

**Delimiter:** A character sequence separating components with defined semantics.

**Prefix:** A keyword categorizing information type, enabling grep-based extraction.

---

## 4. Design Goals

### 4.1 Primary Goals

**G1 - Understanding Atomicity** *(Revised from "Line Atomicity")*

Each greppable line MUST provide complete understanding of its topic. An AI agent retrieving a single line MUST receive sufficient information to act on that topic without requiring adjacent lines.

*Test: Can an agent understand and use this information from this line alone?*

**G2 - Over-Collection** *(New in v1.1.0)*

Grep queries SHOULD return comprehensive topic information. The format MUST encourage information clustering so that related data is retrieved together.

*Test: Does grep for "auth" return everything an agent needs to understand auth?*

**G3 - Topic Orientation** *(New in v1.1.0)*

Information MUST be organized by topic, not by fact type. All information about a function should be retrievable with one topic-based query.

*Test: Can `grep "DETAIL:login"` return everything about login?*

**G4 - Grepability** *(Preserved from v1.0.0)*

Every piece of information MUST be discoverable via pattern matching. Consistent prefixes MUST enable selective extraction.

**G5 - Exhaustive Completeness** *(Preserved from v1.0.0)*

The document MUST contain sufficient information to fully understand the repository.

**G6 - Zero Ambiguity** *(Preserved from v1.0.0)*

Every statement MUST be precise and unambiguous. Types, defaults, constraints, and effects MUST be explicitly stated.

**G7 - Token Efficiency** *(Preserved from v1.0.0)*

While maintaining completeness, the format SHOULD minimize wasteful tokens through structured density rather than abbreviation.

**G8 - Modification Enablement** *(Preserved from v1.0.0)*

The document MUST enable an AI to modify the codebase, not merely understand it.

### 4.2 Non-Goals

- Human readability optimization
- Brevity or summarization
- Visual aesthetics
- Maximum compression at cost of clarity

---

## 5. Format Specification

### 5.1 File Requirements

**5.1.1 Filename:** MUST be `llm.txt` (lowercase)

**5.1.2 Location:** MUST be in repository root

**5.1.3 Encoding:** MUST be UTF-8 without BOM

**5.1.4 Line Endings:** MUST use LF or CRLF consistently

### 5.2 Document Structure

**5.2.1 Header Format** *(Revised in v1.1.0)*

```
# PROJECT-NAME LLM.TXT
# Version: X.Y.Z
# Purpose: Complete repository context for AI agents and LLM systems
# Format: Line-oriented, grepable, topic-oriented knowledge blocks
# License: LICENSE-NAME
# COMMIT_HASH :: <git_short_hash>
# GENERATED_AT :: <ISO8601_timestamp>
# GENERATOR :: <tool_name_version> | manual
```

**New Required Fields:**
- COMMIT_HASH: Git short hash when generated (enables staleness detection)
- GENERATED_AT: ISO8601 timestamp of generation
- GENERATOR: Tool used or "manual"

**5.2.2 Section Structure**

```
================================================================================
[SECTION_NAME]
================================================================================
SECTION_TYPE :: AUTO | MANUAL | HYBRID

content lines...
```

**SECTION_TYPE Values:**
- AUTO: Machine-generated, trust for facts
- MANUAL: Human-written, trust for intent
- HYBRID: Mixed generation

**5.2.3 Separator Lines**

Separator lines SHOULD be 80 equals signs. Implementations MAY use 40-100 equals signs. Consistency within a document is REQUIRED.

**5.2.4 End Marker**

```
================================================================================
[END_OF_DOCUMENT]
================================================================================
```

### 5.3 Line Format

**5.3.1 Summary Line Format** *(New in v1.1.0)*

Summary lines provide complete understanding using inline segments:

```
PREFIX :: primary_content | segment_2 | segment_3 | segment_n
```

Segments are separated by ` | ` (space-pipe-space).

**5.3.2 Detail Line Format** *(New in v1.1.0)*

Detail lines associate with a parent topic:

```
DETAIL:parent_topic :: CATEGORY content
```

**5.3.3 Standard Line Formats** *(Preserved)*

- Key-Value: `PREFIX :: value`
- Hierarchical: `PREFIX >> child`
- Flow: `PREFIX :: step1 -> step2 -> step3`
- Comment: `# comment`
- Blank: Empty line for separation

---

## 6. Section Specifications

### 6.1 Section Categories

- **REQUIRED:** MUST be present
- **CONDITIONAL:** MUST be present if applicable
- **RECOMMENDED:** SHOULD be present
- **OPTIONAL:** MAY be present
- **EXTENSIBLE:** Custom sections permitted

### 6.2 Required Sections

| Section | Purpose | Type Typical |
|---------|---------|--------------|
| GREP_MANUAL | Query instruction | MANUAL |
| TABLE_OF_CONTENTS | Navigation | AUTO |
| PROJECT_IDENTITY | Definition | MANUAL |
| ARCHITECTURE_OVERVIEW | Structure | MANUAL |
| FILE_MANIFEST | Files | AUTO |
| FUNCTION_REFERENCE | Functions | AUTO/HYBRID |
| SCHEMA_DEFINITIONS | Data types | AUTO |
| CONFIGURATION_REFERENCE | Config | HYBRID |
| DATA_FLOW | Flows | MANUAL |
| SECURITY_MODEL | Security | MANUAL |
| DEPENDENCY_REFERENCE | Deps | AUTO |
| TEST_STRUCTURE | Tests | AUTO |
| COMMON_PATTERNS | Patterns | MANUAL |
| TROUBLESHOOTING | Errors | MANUAL |
| FAQ_AI_AGENTS | Questions | MANUAL |
| EDGE_CASES | Edge cases | MANUAL |
| AI_MODIFICATION_GUIDE | Changes | MANUAL |
| FILE_RELATIONSHIPS | Dependencies | AUTO |
| GLOSSARY | Terms | MANUAL |
| DOCUMENT_METADATA | Meta | AUTO |

### 6.3 Section Content - Topic-Oriented Format

#### 6.3.1 [FUNCTION_REFERENCE] *(Revised in v1.1.0)*

**Summary Line Format:**
```
FUNC :: signature | purpose | location | key_behaviors
```

**Components:**
- signature: `name(param:type, ...) -> return_type`
- purpose: Brief description
- location: `LOC:filepath:line_range`
- key_behaviors: `RAISES:x,y | PURE:yes|no | CALLS:a,b`

**Detail Block Format:**
```
DETAIL:function_name :: CATEGORY content
```

**Categories:**
- PARAM: Parameter details
- RETURNS: Return value details
- RAISES: Exception details
- FLOW: Execution flow
- EDGE: Edge case handling
- SECURITY: Security notes
- EXAMPLE: Usage example
- NOTE: Additional context

**Complete Example:**
```
TOPIC :: AUTH_FUNCTIONS
TOPIC_DESCRIPTION :: User authentication and session management
TOPIC_FILES :: ./src/auth.py; ./src/session.py

FUNC :: login(username:str, password:str) -> SessionToken | Validate credentials and create session | LOC:./src/auth.py:45-67 | RAISES:InvalidCredentials,RateLimited | PURE:no | CALLS:hash_password,create_session
DETAIL:login :: PARAM username - user's login identifier; must be valid email format; max 254 chars
DETAIL:login :: PARAM password - plaintext input; hashed via bcrypt(rounds=12) before DB comparison
DETAIL:login :: RETURNS SessionToken - JWT with 24hr expiry; contains user_id, permissions, issued_at
DETAIL:login :: RAISES InvalidCredentials - wrong password OR nonexistent user (prevents enumeration)
DETAIL:login :: RAISES RateLimited - after 5 failures in 15min window per IP
DETAIL:login :: FLOW validate_email_format -> find_user_by_email -> verify_bcrypt_hash -> generate_jwt -> log_auth_event -> return_token
DETAIL:login :: EDGE empty_credentials - immediate InvalidCredentials without DB query
DETAIL:login :: EDGE case_sensitivity - email lowercased; password case-sensitive
DETAIL:login :: SECURITY timing_safe_comparison prevents timing attacks; rate_limiting prevents brute_force

FUNC :: logout(token:str) -> void | Invalidate session token | LOC:./src/auth.py:89-102 | RAISES:none | PURE:no | CALLS:blacklist_token
DETAIL:logout :: PARAM token - JWT string from login; added to Redis blacklist with TTL
DETAIL:logout :: FLOW validate_jwt_format -> add_to_blacklist -> log_logout_event
DETAIL:logout :: EDGE already_logged_out - silently succeeds (idempotent design)
DETAIL:logout :: EDGE expired_token - silently succeeds (already invalid)
```

#### 6.3.2 [FILE_MANIFEST] *(Revised in v1.1.0)*

**Summary Line Format:**
```
FILE :: filename | purpose | LOC:path:lines | CONTAINS:items | EXPORTS:items
```

**Complete Example:**
```
FILE :: auth.py | User authentication and session management | LOC:./src/auth.py:245 | CONTAINS:login,logout,refresh_token,validate_token | EXPORTS:AuthResult,SessionToken
DETAIL:auth.py :: DEPENDS requests; bcrypt; pyjwt
DETAIL:auth.py :: IMPORTS config.settings; db.users; utils.crypto
DETAIL:auth.py :: PATTERNS singleton_db_connection; decorator_rate_limit
```

---

## 7. Delimiter Grammar

### 7.1 Formal Grammar *(Revised in v1.1.0)*

```
line              := summary_line | detail_line | standard_line | comment_line | blank_line

summary_line      := PREFIX DELIM_KV content (DELIM_SEG content)*
detail_line       := "DETAIL:" topic DELIM_KV CATEGORY content
standard_line     := PREFIX DELIM_KV value
                   | PREFIX DELIM_HIER child
                   | PREFIX DELIM_KV step (DELIM_FLOW step)*

PREFIX            := [A-Z][A-Z0-9_]*
CATEGORY          := [A-Z]+
DELIM_KV          := " :: "
DELIM_SEG         := " | "
DELIM_HIER        := " >> "
DELIM_FLOW        := " -> "
DELIM_LIST        := "; "
DELIM_ALT         := " | " (context-dependent)
```

### 7.2 Delimiter Reference

| Delimiter | Name | Usage | Example |
|-----------|------|-------|---------|
| ` :: ` | Key-Value | Primary association | `FILE :: name` |
| ` \| ` | Segment | Inline segments in summary | `a \| b \| c` |
| ` >> ` | Hierarchy | Parent-child | `DIR >> subdir` |
| ` -> ` | Flow | Sequence/causation | `a -> b -> c` |
| `; ` | List | Items in segment | `a; b; c` |
| `()` | Optional | Optional items | `(optional)` |
| `<>` | Placeholder | Required placeholder | `<required>` |
| `:` | Association | In prefixes | `DETAIL:topic` |

---

## 8. Prefix Registry

### 8.1 Core Prefixes

| Prefix | Domain | Summary Line Support | Detail Support |
|--------|--------|---------------------|----------------|
| FILE | Files | Yes | Yes |
| FUNC | Functions | Yes | Yes |
| CLASS | Classes | Yes | Yes |
| CONFIG | Config | Yes | Yes |
| SCHEMA | Schemas | Yes | Yes |
| TOPIC | Topics | Yes | No |
| DETAIL | Details | No | N/A (is detail) |
| FLOW | Flows | Yes | Yes |
| SAFETY | Security | Yes | Yes |
| CMD | Commands | Yes | Yes |
| API | Endpoints | Yes | Yes |

### 8.2 New Prefixes in v1.1.0

| Prefix | Usage | Example |
|--------|-------|---------|
| TOPIC | Topic grouping | `TOPIC :: AUTH_FUNCTIONS` |
| DETAIL | Associated details | `DETAIL:login :: PARAM username` |
| LOC | Source location | `LOC:./src/auth.py:45-67` |

### 8.3 Detail Categories

When using `DETAIL:topic :: CATEGORY`, valid categories include:

| Category | Usage |
|----------|-------|
| PARAM | Parameter documentation |
| RETURNS | Return value documentation |
| RAISES | Exception documentation |
| FLOW | Execution flow |
| EDGE | Edge case handling |
| SECURITY | Security considerations |
| EXAMPLE | Usage examples |
| NOTE | Additional notes |
| DEPENDS | Dependencies |
| IMPORTS | Import statements |
| PATTERNS | Design patterns used |
| CALLS | Functions called |
| CALLEDBY | Functions that call this |

---

## 9. Topic-Oriented Patterns

### 9.1 The Topic Block Pattern

A topic block groups related understanding units:

```
TOPIC :: TOPIC_NAME
TOPIC_DESCRIPTION :: What this topic covers
TOPIC_FILES :: Files involved
TOPIC_RELATED :: Related topics

FUNC :: ... | ... | ... | ...
DETAIL:func1 :: ...
DETAIL:func1 :: ...

FUNC :: ... | ... | ... | ...
DETAIL:func2 :: ...
```

### 9.2 Grep Behavior

| Query | Returns | Completeness |
|-------|---------|--------------|
| `grep "FUNC :: login"` | Summary line | Complete for quick understanding |
| `grep "DETAIL:login"` | All login details | Complete for deep understanding |
| `grep "TOPIC :: AUTH"` | Topic header | Entry point for topic |
| `grep "DETAIL:.*PARAM"` | All params | Cross-cutting view |
| `grep "DETAIL:.*SECURITY"` | All security notes | Security audit |
| `grep "RAISES:InvalidCredentials"` | Functions raising this | Error handling view |

### 9.3 Over-Collection by Design

**Principle:** Related information should appear in multiple greppable locations.

**Implementation:**
```
FUNC :: login(...) | ... | RELATED:logout,validate_token
FUNC :: logout(...) | ... | RELATED:login
FUNC :: validate_token(...) | ... | RELATED:login,logout
```

Grep for "login" returns:
1. Login's own line
2. Appears in RELATED field of logout
3. Appears in RELATED field of validate_token

This is intentional over-collection.

---

## 10. Conformance Levels

### 10.1 Level 1: Minimal Conformance

- File named `llm.txt` in root
- Valid header with integrity fields
- All REQUIRED sections present
- Sections in correct order
- Valid delimiters throughout

### 10.2 Level 2: Standard Conformance

Level 1 plus:
- All files documented with summary lines
- All public functions documented with summary lines
- CONDITIONAL sections present where applicable
- 20+ FAQ entries
- 10+ edge cases
- SECTION_TYPE markers present

### 10.3 Level 3: Full Conformance

Level 2 plus:
- All functions have DETAIL blocks
- All parameters documented
- All flows documented step-by-step
- TOPIC markers for logical groupings
- Complete RELATED cross-references
- Modification guide covers all patterns

---

## 11. Validation Rules

### 11.1 Structural Validation

| Rule | Requirement |
|------|-------------|
| V1 | Header MUST include COMMIT_HASH |
| V2 | Header MUST include GENERATED_AT |
| V3 | All REQUIRED sections MUST be present |
| V4 | Sections MUST be in specified order |
| V5 | SECTION_TYPE SHOULD be present |
| V6 | End marker MUST be present |

### 11.2 Content Validation

| Rule | Requirement |
|------|-------------|
| V7 | Every file MUST have FILE summary line |
| V8 | Every public function MUST have FUNC summary line |
| V9 | Summary lines MUST contain purpose segment |
| V10 | DETAIL lines MUST reference valid parent |
| V11 | LOC references MUST use valid format |

### 11.3 Topic Validation

| Rule | Requirement |
|------|-------------|
| V12 | DETAIL lines MUST follow their parent |
| V13 | TOPIC blocks SHOULD group related items |
| V14 | RELATED fields SHOULD be bidirectional |

---

## 12. Security Considerations

*(Preserved from v1.0.0)*

LLM.TXT files SHOULD NOT contain:
- Credentials or secrets
- API keys
- Private keys
- Internal IP addresses
- Personal information

DETAIL:security blocks SHOULD document security mechanisms without revealing sensitive values.

---

## 13. Implementation Guidance

### 13.1 Generation Strategy

**AUTO Sections:** Generate from code analysis
- FILE_MANIFEST: Parse directory structure
- FUNCTION_REFERENCE: Parse AST for functions
- SCHEMA_DEFINITIONS: Parse type definitions
- DEPENDENCY_REFERENCE: Parse package files

**MANUAL Sections:** Require human input
- PROJECT_IDENTITY: Intent and philosophy
- DATA_FLOW: Architectural decisions
- FAQ_AI_AGENTS: Anticipated questions
- EDGE_CASES: Known quirks

**HYBRID Sections:** Combine both
- FUNCTION_REFERENCE: Auto-generate signatures, manual purpose
- CONFIGURATION_REFERENCE: Auto-detect options, manual explanations

### 13.2 Staleness Detection

Agents SHOULD check:
```python
if llm_commit_hash != current_git_head():
    warn("llm.txt may be stale")
    # Option: regenerate, or proceed with caution
```

### 13.3 Large Repository Strategy

For repos exceeding 50,000 LOC:
- MAY use modular files (llm.txt references llm-auth.txt)
- MUST maintain topic-orientation in each file
- SHOULD include cross-file RELATED references

---

## 14. Examples

### 14.1 Complete Function Block

```
TOPIC :: USER_MANAGEMENT
TOPIC_DESCRIPTION :: User CRUD operations and profile management
TOPIC_FILES :: ./src/users.py; ./src/profiles.py
TOPIC_RELATED :: AUTH_FUNCTIONS; PERMISSION_SYSTEM

FUNC :: create_user(email:str, password:str, name:str) -> User | Create new user account with hashed password | LOC:./src/users.py:23-45 | RAISES:DuplicateEmail,ValidationError | PURE:no | CALLS:hash_password,send_welcome_email
DETAIL:create_user :: PARAM email - must be valid format; checked for uniqueness in DB
DETAIL:create_user :: PARAM password - min 8 chars; hashed with bcrypt before storage
DETAIL:create_user :: PARAM name - display name; max 100 chars; sanitized for XSS
DETAIL:create_user :: RETURNS User object with id, email, name, created_at; password NOT included
DETAIL:create_user :: RAISES DuplicateEmail - if email already registered (case-insensitive)
DETAIL:create_user :: RAISES ValidationError - if any param fails validation
DETAIL:create_user :: FLOW validate_all_params -> check_email_unique -> hash_password -> insert_db -> send_welcome_email -> return_user
DETAIL:create_user :: EDGE empty_name - uses email prefix as default name
DETAIL:create_user :: SECURITY passwords never logged; rate limited to 10 creates/hour/IP
DETAIL:create_user :: EXAMPLE create_user("alice@example.com", "securepass123", "Alice")
```

### 14.2 Complete File Block

```
FILE :: users.py | User CRUD operations and profile management | LOC:./src/users.py:312 | CONTAINS:create_user,get_user,update_user,delete_user,list_users | EXPORTS:User,UserCreate,UserUpdate
DETAIL:users.py :: DEPENDS sqlalchemy; pydantic; bcrypt
DETAIL:users.py :: IMPORTS db.connection; utils.validation; utils.email
DETAIL:users.py :: PATTERNS repository_pattern; dto_validation
DETAIL:users.py :: RELATED auth.py; profiles.py; permissions.py
```

### 14.3 Grep Query Examples

```bash
# Get quick understanding of login
grep "FUNC :: login" llm.txt
# Returns: FUNC :: login(username:str, password:str) -> SessionToken | Validate credentials...

# Get deep understanding of login
grep "DETAIL:login" llm.txt
# Returns: All DETAIL:login lines (params, returns, flow, edges, security)

# Find all functions that raise InvalidCredentials
grep "RAISES:.*InvalidCredentials" llm.txt
# Returns: All FUNC lines with this exception

# Find all security considerations
grep "DETAIL:.*SECURITY" llm.txt
# Returns: All security notes across all functions

# Find all edge cases
grep "DETAIL:.*EDGE" llm.txt
# Returns: All edge case documentation

# Find everything about auth
grep -E "(TOPIC :: AUTH|FUNC :: login|FUNC :: logout|DETAIL:login|DETAIL:logout)" llm.txt
# Returns: Complete auth topic coverage
```

---

## 15. Migration from v1.0.0

### 15.1 Compatibility

| v1.0.0 Feature | v1.1.0 Status |
|----------------|---------------|
| Basic prefixes | Preserved |
| :: delimiter | Preserved |
| >> hierarchy | Preserved |
| -> flow | Preserved |
| Section structure | Preserved |
| Atomic fact lines | Deprecated |

### 15.2 Migration Steps

1. **Add integrity headers** to document header
2. **Add SECTION_TYPE** to each section
3. **Convert FUNC blocks** to summary line + DETAIL blocks
4. **Convert FILE entries** to summary line format
5. **Add TOPIC markers** for logical groupings
6. **Add RELATED fields** for cross-references
7. **Update GREP_MANUAL** with new patterns

### 15.3 Migration Example

**Before (v1.0.0):**
```
FUNC :: login()
FUNC_FILE :: ./src/auth.py
FUNC_SIGNATURE :: login(username: str, password: str) -> SessionToken
FUNC_PURPOSE :: Validate user credentials
FUNC_PARAM :: username (str) - user's login identifier
FUNC_PARAM :: password (str) - user's password
FUNC_RETURNS :: SessionToken on success
FUNC_THROWS :: InvalidCredentials on failure
```

**After (v1.1.0):**
```
FUNC :: login(username:str, password:str) -> SessionToken | Validate user credentials | LOC:./src/auth.py:45-67 | RAISES:InvalidCredentials | PURE:no
DETAIL:login :: PARAM username (str) - user's login identifier
DETAIL:login :: PARAM password (str) - user's password
DETAIL:login :: RETURNS SessionToken on success
DETAIL:login :: RAISES InvalidCredentials on failure
```

---

## 16. References

### 16.1 Normative References

- RFC 2119: Requirement level keywords
- RFC-LLM-TXT-001-REVISIONS: Revision history and decisions

### 16.2 Informative References

- robots.txt: Prior art for machine-oriented files
- Topic Modeling: Information retrieval theory

---

## Appendix A: Complete Section Reference

*(See v1.0.0 Appendix A, with additions below)*

### A.21 [TOPIC] Markers

**Purpose:** Group related understanding units

**Format:**
```
TOPIC :: TOPIC_NAME
TOPIC_DESCRIPTION :: What this covers
TOPIC_FILES :: file1; file2
TOPIC_RELATED :: other_topic1; other_topic2
```

---

## Appendix B: Prefix Quick Reference

| Prefix | Summary Support | Detail Support | New in 1.1 |
|--------|-----------------|----------------|------------|
| FILE | Yes | Yes | No |
| FUNC | Yes | Yes | No |
| CLASS | Yes | Yes | No |
| TOPIC | Yes | No | Yes |
| DETAIL | No | N/A | Yes |
| LOC | Inline | No | Yes |

---

## Appendix C: Conformance Checklist

### Level 1 Checklist

- [ ] File named `llm.txt`
- [ ] COMMIT_HASH in header
- [ ] GENERATED_AT in header
- [ ] All REQUIRED sections present
- [ ] Valid delimiters throughout
- [ ] End marker present

### Level 2 Checklist

- [ ] Level 1 complete
- [ ] All files have summary lines
- [ ] All functions have summary lines
- [ ] SECTION_TYPE markers present
- [ ] 20+ FAQ entries
- [ ] 10+ edge cases

### Level 3 Checklist

- [ ] Level 2 complete
- [ ] All functions have DETAIL blocks
- [ ] TOPIC markers for groupings
- [ ] RELATED cross-references
- [ ] Complete FLOW documentation
- [ ] All EDGE cases documented

---

## Authors' Addresses

LLM.TXT Working Group

Contributors:
- Human Maintainer (philosophy, topic-orientation)
- Claude, Anthropic (synthesis, specification)
- Gemini, Google (review, integrity headers)

---

*End of RFC-LLM-TXT-001 v1.1.0*
