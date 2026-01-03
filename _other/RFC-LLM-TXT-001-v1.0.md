# RFC-LLM-TXT-001: LLM.TXT Repository Documentation Format Specification

```
Request for Comments: LLM-TXT-001
Category: Standards Track
Status: Proposed Standard
Version: 1.0.0
Date: January 2026
Author: AI Documentation Working Group
```

## Status of This Memo

This document specifies a proposed standard format for repository documentation optimized for consumption by Large Language Models (LLMs) and AI agent systems. Distribution of this memo is unlimited.

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
9. [Conformance Levels](#9-conformance-levels)
10. [Validation Rules](#10-validation-rules)
11. [Security Considerations](#11-security-considerations)
12. [IANA Considerations](#12-iana-considerations)
13. [Implementation Guidance](#13-implementation-guidance)
14. [Examples](#14-examples)
15. [References](#15-references)
16. [Appendix A: Complete Section Reference](#appendix-a-complete-section-reference)
17. [Appendix B: Prefix Quick Reference](#appendix-b-prefix-quick-reference)
18. [Appendix C: Conformance Checklist](#appendix-c-conformance-checklist)

---

## 1. Abstract

This document defines LLM.TXT, a standardized format for repository documentation designed specifically for machine comprehension by Large Language Models and AI agent systems. The format prioritizes line-oriented atomicity, grep-based discoverability, exhaustive completeness, and zero-ambiguity documentation.

LLM.TXT addresses the growing need for AI systems to understand, utilize, and modify codebases without human intermediation. Traditional documentation formats (README, wiki, inline comments) are optimized for human readers and prove inadequate for AI consumption due to their reliance on implicit context, prose-based structure, and incomplete coverage.

The specification defines a line-oriented, delimiter-based format that enables:
- Selective knowledge extraction via pattern matching (grep)
- Complete repository comprehension from a single file
- Unambiguous interpretation without contextual inference
- Modification guidance for AI-driven code changes

---

## 2. Introduction

### 2.1 Problem Statement

AI systems interacting with codebases face significant challenges:

1. **Fragmented Documentation**: Information spread across README, comments, wikis, and tribal knowledge
2. **Implicit Context**: Documentation assumes human background knowledge
3. **Prose-Optimized Formats**: Narrative text difficult to parse programmatically
4. **Incomplete Coverage**: Critical details omitted as "obvious"
5. **Discovery Difficulty**: No standardized way to locate specific information

### 2.2 Solution Overview

LLM.TXT provides a single, comprehensive file containing all repository knowledge in a format optimized for AI consumption. Key characteristics:

- **Single File**: All knowledge in one location (`llm.txt`)
- **Line Atomicity**: Each line is a complete knowledge unit
- **Grepability**: Consistent prefixes enable pattern-based extraction
- **Exhaustive**: Documents everything, assumes nothing
- **Actionable**: Enables AI to understand, use, and modify code

### 2.3 Scope

This specification covers:
- File format and structure
- Required and optional sections
- Delimiter and prefix conventions
- Conformance levels and validation
- Implementation guidance

This specification does not cover:
- Specific programming language documentation patterns (see companion documents)
- Integration with development tools
- Automated generation mechanisms

### 2.4 Document Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

---

## 3. Terminology

### 3.1 Definitions

**LLM.TXT**: A plain text file named `llm.txt` located in a repository root, containing comprehensive documentation in the format specified by this document.

**Line**: A sequence of characters terminated by a newline character (LF or CRLF). The fundamental unit of information in LLM.TXT.

**Section**: A logical grouping of related lines, bounded by section headers. Sections organize knowledge by domain.

**Section Header**: A line containing a section name enclosed in square brackets, preceded and followed by separator lines.

**Delimiter**: A character sequence used to separate components within a line. Delimiters have defined semantic meanings.

**Prefix**: A keyword at the beginning of a line that categorizes the information type. Prefixes enable grep-based extraction.

**Atomic Line**: A line that provides complete, self-contained information without requiring adjacent lines for interpretation.

**Grepability**: The property of information being discoverable via pattern matching (grep or equivalent).

**Knowledge Unit**: A discrete piece of information that can be independently understood and applied.

### 3.2 Abbreviations

- LLM: Large Language Model
- AI: Artificial Intelligence
- TOC: Table of Contents
- FAQ: Frequently Asked Questions
- API: Application Programming Interface
- CLI: Command Line Interface

---

## 4. Design Goals

### 4.1 Primary Goals

**G1 - Line Atomicity**: Every line MUST be independently meaningful. An AI extracting a single line MUST receive complete information about that line's topic.

**G2 - Grepability**: Every piece of information MUST be discoverable via pattern matching. Consistent prefixes MUST enable selective extraction of knowledge domains.

**G3 - Exhaustive Completeness**: The document MUST contain sufficient information to fully understand the repository. All files, functions, configurations, and behaviors MUST be documented.

**G4 - Zero Ambiguity**: Every statement MUST be precise and unambiguous. Types, defaults, constraints, and effects MUST be explicitly stated.

**G5 - Token Efficiency**: While maintaining completeness, the format SHOULD minimize wasteful tokens. Decorative formatting SHOULD be avoided.

**G6 - Modification Enablement**: The document MUST enable an AI to modify the codebase, not merely understand it.

### 4.2 Non-Goals

The following are explicitly NOT goals of this specification:

- Human readability optimization (though the format remains human-readable)
- Brevity or summarization
- Visual aesthetics
- Compatibility with existing documentation tools
- Automatic generation (implementation concern, not format concern)

---

## 5. Format Specification

### 5.1 File Requirements

**5.1.1 Filename**

The file MUST be named `llm.txt` (lowercase).

**5.1.2 Location**

The file MUST be located in the repository root directory.

**5.1.3 Encoding**

The file MUST be encoded as UTF-8 without BOM.

**5.1.4 Line Endings**

The file MUST use either LF (Unix) or CRLF (Windows) line endings consistently throughout.

### 5.2 Document Structure

**5.2.1 Overall Structure**

An LLM.TXT document consists of:
1. Header (lines 1-6)
2. Separator line
3. Sections (in specified order)
4. End marker

**5.2.2 Header Format**

The document MUST begin with a header block:

```
# PROJECT-NAME LLM.TXT
# Version: X.Y.Z
# Purpose: Complete repository context for AI agents and LLM systems
# Format: Line-oriented, grepable, information-dense prose
# License: LICENSE-NAME
```

Fields:
- PROJECT-NAME: Repository/project name (REQUIRED)
- Version: Semantic version of the llm.txt (REQUIRED)
- Purpose: Fixed string as shown (REQUIRED)
- Format: Fixed string as shown (REQUIRED)
- License: Project license identifier (OPTIONAL)

**5.2.3 Section Structure**

Each section MUST follow this structure:

```
================================================================================
[SECTION_NAME]
================================================================================

content lines...
```

Requirements:
- Separator lines MUST be exactly 80 equals signs
- Section name MUST be uppercase with underscores
- Section name MUST be enclosed in square brackets
- Blank line MUST follow the closing separator

**5.2.4 End Marker**

The document MUST end with:

```
================================================================================
[END_OF_DOCUMENT]
================================================================================
```

### 5.3 Line Format

**5.3.1 General Line Format**

Lines MUST follow one of these formats:

1. **Key-Value Line**: `PREFIX :: value`
2. **Hierarchical Line**: `PREFIX >> child_item`
3. **Flow Line**: `PREFIX :: step1 -> step2 -> step3`
4. **Comment Line**: `# comment text`
5. **Blank Line**: Empty line for visual separation

**5.3.2 Line Length**

Lines SHOULD NOT exceed 120 characters. Exceptions:
- Long file paths
- Long function signatures
- URLs

**5.3.3 Line Independence**

Each content line MUST be interpretable without reference to adjacent lines. If information requires multiple lines, each line MUST include sufficient context.

Example (CORRECT):
```
FUNC_PARAM :: user_id (string) - unique identifier for the user
FUNC_PARAM :: email (string) - user's email address
```

Example (INCORRECT):
```
FUNC_PARAM :: user_id - unique identifier
FUNC_PARAM :: email - see above for type
```

---

## 6. Section Specifications

### 6.1 Section Categories

Sections are categorized as:
- **REQUIRED**: MUST be present in all conforming documents
- **CONDITIONAL**: MUST be present if applicable to the project type
- **RECOMMENDED**: SHOULD be present for most projects
- **OPTIONAL**: MAY be present based on project needs
- **EXTENSIBLE**: Custom sections MAY be added

### 6.2 Required Sections

The following sections MUST be present:

| Section | Purpose |
|---------|---------|
| GREP_MANUAL | Teaches querying patterns |
| TABLE_OF_CONTENTS | Navigation index |
| PROJECT_IDENTITY | Project definition |
| ARCHITECTURE_OVERVIEW | System structure |
| FILE_MANIFEST | File documentation |
| FUNCTION_REFERENCE | Function documentation |
| SCHEMA_DEFINITIONS | Data structures |
| CONFIGURATION_REFERENCE | Config options |
| DATA_FLOW | Operation flows |
| SECURITY_MODEL | Security mechanisms |
| DEPENDENCY_REFERENCE | Dependencies |
| TEST_STRUCTURE | Test organization |
| COMMON_PATTERNS | Code patterns |
| TROUBLESHOOTING | Error resolution |
| FAQ_AI_AGENTS | Anticipated questions |
| EDGE_CASES | Unusual scenarios |
| AI_MODIFICATION_GUIDE | Change instructions |
| FILE_RELATIONSHIPS | Dependency graph |
| GLOSSARY | Term definitions |
| DOCUMENT_METADATA | Document info |

### 6.3 Conditional Sections

These sections MUST be present when applicable:

| Section | Condition |
|---------|-----------|
| CLI_REFERENCE | Project has CLI |
| API_ENDPOINTS | Project has HTTP API |
| CLASS_REFERENCE | OOP language with classes |
| EXIT_CODES | CLI with exit codes |
| ERROR_CODES | Library with error types |
| ENVIRONMENT_VARIABLES | Uses env vars |
| DATABASE_SCHEMA | Has database |
| COMPONENT_REFERENCE | Has UI components |
| EVENT_REFERENCE | Event-driven system |
| MESSAGE_FORMATS | Message-based system |

### 6.4 Section Order

Sections MUST appear in the following order:

1. GREP_MANUAL
2. TABLE_OF_CONTENTS
3. PROJECT_IDENTITY
4. ARCHITECTURE_OVERVIEW
5. FILE_MANIFEST
6. FUNCTION_REFERENCE
7. (Conditional: CLASS_REFERENCE)
8. (Conditional: API_ENDPOINTS)
9. (Conditional: CLI_REFERENCE)
10. SCHEMA_DEFINITIONS
11. CONFIGURATION_REFERENCE
12. (Conditional: ENVIRONMENT_VARIABLES)
13. (Conditional: EXIT_CODES, ERROR_CODES)
14. DATA_FLOW
15. SECURITY_MODEL
16. DEPENDENCY_REFERENCE
17. TEST_STRUCTURE
18. (Recommended: INTERNAL_API_CONTRACTS)
19. COMMON_PATTERNS
20. TROUBLESHOOTING
21. FAQ_AI_AGENTS
22. EDGE_CASES
23. (Optional: KNOWN_LIMITATIONS)
24. (Optional: FUTURE_ROADMAP)
25. AI_MODIFICATION_GUIDE
26. FILE_RELATIONSHIPS
27. GLOSSARY
28. (Recommended: QUICK_REFERENCE)
29. DOCUMENT_METADATA

Custom sections MAY be inserted at logical positions.

### 6.5 Section Content Requirements

#### 6.5.1 [GREP_MANUAL]

MUST contain:
- Pattern example for each prefix used in document
- Expected result description for each pattern
- Delimiter reference

Example:
```
GREP_PATTERN :: grep "FILE::" llm.txt
GREP_RESULT :: Returns all file paths with their purposes

DELIMITER_REFERENCE :: Key-value pairs use ::
DELIMITER_REFERENCE :: Hierarchy uses >>
```

#### 6.5.2 [TABLE_OF_CONTENTS]

MUST contain:
- TOC_LINE entry for each section with approximate line number
- SECTION_COUNT with total section count
- LINE_COUNT with total line count

Example:
```
TOC_LINE :: 008 - [GREP_MANUAL] - Query instruction
TOC_LINE :: 050 - [PROJECT_IDENTITY] - Project definition
SECTION_COUNT :: 24
LINE_COUNT :: 1600
```

#### 6.5.3 [PROJECT_IDENTITY]

MUST contain:
- PROJECT_NAME
- PROJECT_TYPE
- PROJECT_LANGUAGE
- PROJECT_LICENSE
- At least 3 INTENT statements
- At least 2 TARGET_USER statements

SHOULD contain:
- PROJECT_STATUS
- PHILOSOPHY statements
- ANTI_USER statements

#### 6.5.4 [FILE_MANIFEST]

MUST document every file with:
- FILE :: filename
- FILE_PATH :: path
- FILE_LINES :: count
- FILE_PURPOSE :: description

SHOULD include:
- FILE_CONTAINS :: key contents
- FILE_EXPORTS :: exports
- FILE_REQUIRES :: dependencies

#### 6.5.5 [FUNCTION_REFERENCE]

MUST document every public/exported function with:
- FUNC :: name()
- FUNC_FILE :: location
- FUNC_SIGNATURE :: full signature
- FUNC_PURPOSE :: description

SHOULD include:
- FUNC_PARAM for each parameter
- FUNC_RETURNS
- FUNC_THROWS
- FUNC_PURE :: yes|no

#### 6.5.6 [FAQ_AI_AGENTS]

MUST contain at least:
- 20 FAQ entries for simple projects
- 50 FAQ entries for complex projects

Each entry MUST have:
- FAQ :: question
- FAQ_ANSWER :: complete answer

Questions SHOULD cover:
- What is this project?
- How to install/use?
- How to configure?
- Where are key files?
- How to modify/extend?
- Common error resolutions

#### 6.5.7 [EDGE_CASES]

MUST document at least 10 edge cases.

Each entry MUST have:
- EDGE :: scenario
- EDGE_BEHAVIOR :: what happens

SHOULD include:
- EDGE_LOGGED
- EDGE_EXIT
- EDGE_RECOVERY

---

## 7. Delimiter Grammar

### 7.1 Formal Grammar

```
line            := prefix_line | hierarchy_line | flow_line | comment_line | blank_line
prefix_line     := PREFIX DELIMITER_KV value
hierarchy_line  := PREFIX DELIMITER_HIER child
flow_line       := PREFIX DELIMITER_KV step (DELIMITER_FLOW step)*
comment_line    := "#" text
blank_line      := ""

PREFIX          := [A-Z][A-Z0-9_]*
DELIMITER_KV    := " :: "
DELIMITER_HIER  := " >> "
DELIMITER_FLOW  := " -> "
DELIMITER_LIST  := "; "
DELIMITER_ALT   := " | "

value           := text | list | alternatives
list            := item (DELIMITER_LIST item)*
alternatives    := option (DELIMITER_ALT option)*
```

### 7.2 Delimiter Semantics

| Delimiter | Meaning | Example |
|-----------|---------|---------|
| ` :: ` | Key-value association | `FILE_PATH :: ./src/main.py` |
| ` >> ` | Hierarchical containment | `DIR >> subdir/ - description` |
| ` -> ` | Sequential flow | `input -> process -> output` |
| `; ` | List items | `a; b; c` |
| ` \| ` | Alternatives | `DEBUG \| INFO \| ERROR` |
| `()` | Optional | `--flag (--optional)` |
| `<>` | Required placeholder | `--input <file>` |

### 7.3 Spacing Requirements

- Delimiters MUST have single space on each side
- Exception: `()` and `<>` have no surrounding spaces
- List items MUST have semicolon followed by single space

---

## 8. Prefix Registry

### 8.1 Core Prefixes

These prefixes are REQUIRED to be supported:

| Prefix | Domain | Description |
|--------|--------|-------------|
| FILE | Files | File documentation |
| FUNC | Functions | Function documentation |
| CLASS | Classes | Class documentation |
| CONFIG | Configuration | Config options |
| SCHEMA | Schemas | Data structures |
| FLOW | Data Flow | Operation flows |
| SAFETY | Security | Security mechanisms |
| DEPEND | Dependencies | Requirements |
| TEST | Testing | Test information |
| CMD | Commands | CLI commands |
| API | APIs | Endpoints |
| EXIT | Exit Codes | Process exit codes |
| ERR | Errors | Error codes |
| FAQ | FAQs | Questions and answers |
| EDGE | Edge Cases | Unusual scenarios |
| MOD | Modification | Change guidance |
| REL | Relationships | File dependencies |
| TROUBLE | Troubleshooting | Error resolution |
| TERM | Glossary | Definitions |
| META | Metadata | Document info |

### 8.2 Prefix Variants

Each prefix MAY have variants using underscore suffixes:

```
FILE           - Base prefix
FILE_PATH      - Specific variant
FILE_LINES     - Specific variant
FILE_PURPOSE   - Specific variant
```

### 8.3 Custom Prefixes

Implementations MAY define custom prefixes for project-specific needs.

Custom prefixes:
- MUST be uppercase
- MUST use only letters, numbers, underscores
- SHOULD be documented in GREP_MANUAL
- MUST be used consistently throughout

---

## 9. Conformance Levels

### 9.1 Level 1: Minimal Conformance

A document achieves Level 1 conformance if:
- File is named `llm.txt`
- File is in repository root
- File has valid header
- All REQUIRED sections are present
- Section order is correct
- All lines use valid delimiters

### 9.2 Level 2: Standard Conformance

A document achieves Level 2 conformance if:
- Level 1 requirements are met
- All CONDITIONAL sections are present when applicable
- FILE_MANIFEST documents all files
- FUNCTION_REFERENCE documents all public functions
- FAQ_AI_AGENTS has minimum required entries
- EDGE_CASES has minimum required entries

### 9.3 Level 3: Full Conformance

A document achieves Level 3 conformance if:
- Level 2 requirements are met
- All RECOMMENDED sections are present
- All functions have complete documentation (params, returns, throws)
- All schemas have complete field documentation
- All config options have defaults documented
- All flows have step-by-step documentation
- Modification guide covers all common changes
- File relationships are complete

---

## 10. Validation Rules

### 10.1 Structural Validation

**V1**: Header MUST be present and complete
**V2**: All REQUIRED sections MUST be present
**V3**: Sections MUST be in specified order
**V4**: Section headers MUST use correct format
**V5**: End marker MUST be present

### 10.2 Content Validation

**V6**: Every file in repository MUST have FILE entry
**V7**: Every public function MUST have FUNC entry
**V8**: Every CONFIG option MUST have default
**V9**: Every SCHEMA field MUST have type
**V10**: Every FAQ MUST have FAQ_ANSWER

### 10.3 Format Validation

**V11**: Lines MUST use valid delimiters
**V12**: Prefixes MUST be uppercase
**V13**: Section names MUST be uppercase with underscores
**V14**: Separator lines MUST be 80 characters

### 10.4 Consistency Validation

**V15**: Same prefix MUST be used for same concept throughout
**V16**: File paths MUST be consistent (relative or absolute)
**V17**: Function signatures MUST match code
**V18**: Line counts MUST be accurate

---

## 11. Security Considerations

### 11.1 Sensitive Information

LLM.TXT files SHOULD NOT contain:
- Credentials or secrets
- API keys
- Private keys
- Internal IP addresses
- Personal information

If the repository contains sensitive patterns, the SECURITY_MODEL section SHOULD document how they are protected without revealing the actual values.

### 11.2 Path Traversal

FILE_PATH entries SHOULD use relative paths from repository root to prevent path confusion.

### 11.3 Code Injection

LLM.TXT is plain text and contains no executable code. Consumers SHOULD NOT execute any content from LLM.TXT directly.

---

## 12. IANA Considerations

This document has no IANA actions.

The filename `llm.txt` follows the pattern of `robots.txt` and `humans.txt` as a conventional filename for machine-oriented documentation.

---

## 13. Implementation Guidance

### 13.1 Generation

LLM.TXT files MAY be generated manually or automatically.

Automatic generation SHOULD:
- Parse source files for functions, classes, exports
- Extract configuration from config files
- Generate FAQ from common documentation queries
- Validate completeness before output

### 13.2 Maintenance

LLM.TXT files SHOULD be updated when:
- Files are added or removed
- Functions are added, removed, or modified
- Configuration options change
- APIs change
- Dependencies change

Version field SHOULD be incremented on updates.

### 13.3 Integration

LLM.TXT MAY be integrated with:
- CI/CD pipelines for validation
- Documentation generators
- IDE plugins
- AI coding assistants

### 13.4 Size Considerations

For very large repositories:
- LLM.TXT MAY exceed 10,000 lines
- Implementations SHOULD support streaming reads
- TOC becomes critical for navigation
- Consider modular documentation with references

---

## 14. Examples

### 14.1 Minimal Conforming Document

```
# EXAMPLE LLM.TXT
# Version: 1.0.0
# Purpose: Complete repository context for AI agents and LLM systems
# Format: Line-oriented, grepable, information-dense prose

================================================================================
[GREP_MANUAL]
================================================================================

GREP_PATTERN :: grep "FILE::" llm.txt
GREP_RESULT :: Returns all file documentation

================================================================================
[TABLE_OF_CONTENTS]
================================================================================

TOC_LINE :: 001 - [GREP_MANUAL]
TOC_LINE :: 010 - [PROJECT_IDENTITY]
SECTION_COUNT :: 20
LINE_COUNT :: 200

================================================================================
[PROJECT_IDENTITY]
================================================================================

PROJECT_NAME :: example
PROJECT_TYPE :: library
PROJECT_LANGUAGE :: Python
PROJECT_LICENSE :: MIT
INTENT :: Demonstrate llm.txt format
INTENT :: Provide minimal example
INTENT :: Enable validation testing
TARGET_USER :: Developers
TARGET_USER :: AI agents

... (remaining required sections) ...

================================================================================
[DOCUMENT_METADATA]
================================================================================

META_VERSION :: 1.0.0
META_LINES :: 200

================================================================================
[END_OF_DOCUMENT]
================================================================================
```

### 14.2 Function Documentation Example

```
FUNC :: authenticate_user()
FUNC_FILE :: ./src/auth/authentication.py
FUNC_SIGNATURE :: authenticate_user(username: str, password: str, mfa_code: Optional[str] = None) -> AuthResult
FUNC_PURPOSE :: Validate user credentials and return authentication result
FUNC_PARAM :: username (str) - user's login identifier; must be non-empty
FUNC_PARAM :: password (str) - user's password; will be hashed before comparison
FUNC_PARAM :: mfa_code (Optional[str]) - multi-factor auth code; required if user has MFA enabled
FUNC_RETURNS :: AuthResult object with success status; user_id if successful; error_code if failed
FUNC_THROWS :: ValidationError - if username or password is empty
FUNC_THROWS :: RateLimitError - if too many failed attempts
FUNC_PURE :: no
FUNC_ASYNC :: no
```

### 14.3 FAQ Example

```
FAQ :: How do I add a new API endpoint?
FAQ_ANSWER :: 1. Create handler function in ./src/handlers/
FAQ_ANSWER :: 2. Add route in ./src/routes.py
FAQ_ANSWER :: 3. Add schema in ./src/schemas/ if needed
FAQ_ANSWER :: 4. Add tests in ./tests/test_handlers/
FAQ_ANSWER :: 5. Update API_ENDPOINTS in llm.txt
```

---

## 15. References

### 15.1 Normative References

- RFC 2119: Key words for use in RFCs to Indicate Requirement Levels
- Unicode Standard: Character encoding

### 15.2 Informative References

- robots.txt: Prior art for machine-oriented repository files
- humans.txt: Prior art for conventional documentation files
- JSON Lines: Inspiration for line-oriented format

---

## Appendix A: Complete Section Reference

### A.1 [GREP_MANUAL]

**Purpose**: Teach AI agents how to query the document

**Required Content**:
- GREP_PATTERN for each prefix
- GREP_RESULT for each pattern
- DELIMITER_REFERENCE entries

### A.2 [TABLE_OF_CONTENTS]

**Purpose**: Navigation index

**Required Content**:
- TOC_LINE for each section
- SECTION_COUNT
- LINE_COUNT

### A.3 [PROJECT_IDENTITY]

**Purpose**: Define what this project is

**Required Content**:
- PROJECT_NAME
- PROJECT_TYPE
- PROJECT_LANGUAGE
- PROJECT_LICENSE
- INTENT (3+ entries)
- TARGET_USER (2+ entries)

### A.4 [ARCHITECTURE_OVERVIEW]

**Purpose**: Describe system structure

**Required Content**:
- ARCH_STYLE
- LAYER definitions
- FLOW descriptions

### A.5 [FILE_MANIFEST]

**Purpose**: Document all files

**Required Content**:
- FILE entry for each file
- FILE_PATH
- FILE_PURPOSE

### A.6 [FUNCTION_REFERENCE]

**Purpose**: Document all functions

**Required Content**:
- FUNC entry for each function
- FUNC_FILE
- FUNC_SIGNATURE
- FUNC_PURPOSE

### A.7 [SCHEMA_DEFINITIONS]

**Purpose**: Document data structures

**Required Content**:
- SCHEMA entry for each type
- SCHEMA_FIELD entries

### A.8 [CONFIGURATION_REFERENCE]

**Purpose**: Document config options

**Required Content**:
- CONFIG entry for each option
- CONFIG_DEFAULT

### A.9 [DATA_FLOW]

**Purpose**: Document operation flows

**Required Content**:
- FLOW entry for major operations
- FLOW_STEP sequences

### A.10 [SECURITY_MODEL]

**Purpose**: Document security mechanisms

**Required Content**:
- SAFETY entry for each mechanism
- SAFETY_DESCRIPTION
- SAFETY_LOCATION

### A.11 [DEPENDENCY_REFERENCE]

**Purpose**: Document dependencies

**Required Content**:
- DEPEND entry for each dependency
- DEPEND_TYPE (required/optional)

### A.12 [TEST_STRUCTURE]

**Purpose**: Document test organization

**Required Content**:
- TEST_DIR entries
- TEST_FILE entries

### A.13 [COMMON_PATTERNS]

**Purpose**: Document code patterns

**Required Content**:
- PATTERN entries with code examples

### A.14 [TROUBLESHOOTING]

**Purpose**: Document error resolution

**Required Content**:
- TROUBLE entries
- TROUBLE_CAUSE
- TROUBLE_FIX

### A.15 [FAQ_AI_AGENTS]

**Purpose**: Answer anticipated questions

**Required Content**:
- FAQ entries (20-50+)
- FAQ_ANSWER for each

### A.16 [EDGE_CASES]

**Purpose**: Document unusual scenarios

**Required Content**:
- EDGE entries (10+)
- EDGE_BEHAVIOR

### A.17 [AI_MODIFICATION_GUIDE]

**Purpose**: Guide code modifications

**Required Content**:
- MOD entries for common changes
- MOD_STEP sequences

### A.18 [FILE_RELATIONSHIPS]

**Purpose**: Document dependencies

**Required Content**:
- REL entries
- REL_TYPE

### A.19 [GLOSSARY]

**Purpose**: Define terms

**Required Content**:
- TERM entries
- TERM_DEFINITION

### A.20 [DOCUMENT_METADATA]

**Purpose**: Document info

**Required Content**:
- META_VERSION
- META_LINES

---

## Appendix B: Prefix Quick Reference

| Prefix | Usage |
|--------|-------|
| API | API endpoints |
| ARCH | Architecture |
| CLASS | Classes |
| CMD | CLI commands |
| CONFIG | Configuration |
| DEPEND | Dependencies |
| EDGE | Edge cases |
| ERR | Error codes |
| EXIT | Exit codes |
| FAQ | FAQ entries |
| FILE | Files |
| FLOW | Data flows |
| FUNC | Functions |
| GREP | Grep patterns |
| INTENT | Design intent |
| LAYER | Architecture layers |
| META | Metadata |
| MOD | Modifications |
| PATTERN | Code patterns |
| QUICK | Quick reference |
| REL | Relationships |
| SAFETY | Security |
| SCHEMA | Schemas |
| TERM | Glossary |
| TEST | Tests |
| TOC | Table of contents |
| TROUBLE | Troubleshooting |
| WARN | Warnings |

---

## Appendix C: Conformance Checklist

### Level 1 Checklist

- [ ] File named `llm.txt`
- [ ] File in repository root
- [ ] Valid header present
- [ ] [GREP_MANUAL] present
- [ ] [TABLE_OF_CONTENTS] present
- [ ] [PROJECT_IDENTITY] present
- [ ] [ARCHITECTURE_OVERVIEW] present
- [ ] [FILE_MANIFEST] present
- [ ] [FUNCTION_REFERENCE] present
- [ ] [SCHEMA_DEFINITIONS] present
- [ ] [CONFIGURATION_REFERENCE] present
- [ ] [DATA_FLOW] present
- [ ] [SECURITY_MODEL] present
- [ ] [DEPENDENCY_REFERENCE] present
- [ ] [TEST_STRUCTURE] present
- [ ] [COMMON_PATTERNS] present
- [ ] [TROUBLESHOOTING] present
- [ ] [FAQ_AI_AGENTS] present
- [ ] [EDGE_CASES] present
- [ ] [AI_MODIFICATION_GUIDE] present
- [ ] [FILE_RELATIONSHIPS] present
- [ ] [GLOSSARY] present
- [ ] [DOCUMENT_METADATA] present
- [ ] [END_OF_DOCUMENT] present
- [ ] Section order correct
- [ ] All delimiters valid

### Level 2 Checklist

- [ ] Level 1 complete
- [ ] All files documented
- [ ] All public functions documented
- [ ] 20+ FAQ entries
- [ ] 10+ edge cases
- [ ] Conditional sections present where applicable

### Level 3 Checklist

- [ ] Level 2 complete
- [ ] All function parameters documented
- [ ] All function returns documented
- [ ] All config defaults documented
- [ ] All schema fields typed
- [ ] All flows have steps
- [ ] Modification guide complete
- [ ] File relationships complete

---

## Authors' Addresses

AI Documentation Working Group
llm-txt-spec@example.org

---

*End of RFC-LLM-TXT-001*
