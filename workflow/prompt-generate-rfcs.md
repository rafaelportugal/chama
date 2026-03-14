# Generate RFCs from Ideas

Read the idea source (GitHub Issue or file).

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
```

For each idea, create an RFC as a GitHub Issue with label `rfc`:

```bash
gh issue create --repo "$REPO" --label "rfc" --title "rfc: <Title>" --body "<RFC body>"
```

## RFC Structure

Each RFC Issue should follow this template:

```markdown
# RFC: Feature Name

---

## 1. Context

### What this section answers
- What problem exists today?
- Why does this matter for the business and the system?
- What is missing in the current state?

Focus **exclusively on the problem**, without discussing solutions.

---

## 2. Objective

### What this section answers
- What do we want to achieve with this RFC?
- How will we know the initiative was successful?

Describe the **expected result**, not the implementation.

---

## 3. Scope

#### Includes
- ...

#### Does not include
- ...

---

## 4. Personas / Impacted Users

- **Role**: Description of how they're impacted

---

## 5. Functional Requirements

- RF1: ...
- RF2: ...

---

## 6. Non-Functional Requirements

- Performance
- Security
- Observability
- Scalability

---

## 7. Main Flows

### Flow name
1. Step 1
2. Step 2

---

## 8. Dependencies

- ...

---

## 9. Risks and Trade-offs

- ...

---

## 10. Success Metrics

- ...

---

## 11. Acceptance Criteria

- [ ] ...

---

## 12. Technical Details

Include SQL schema, models, endpoints as needed.

---

## 13. Open Questions

- ...

---

## 14. Status

- **Author**: ...
- **Date**: YYYY-MM-DD
- **State**: Draft
```

When all ideas have been converted to RFCs, stop.
