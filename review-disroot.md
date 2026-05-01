---
description: Commit and force push changes to remote (single commit clean history) - auto-generates title and message based on changes
agent: build
---

You are responsible for committing and pushing changes to the git repository with a clean history.

---

## Step 1: Check for Uncommitted Changes (EXECUTE BASH)

```bash
git status --short
```

**IF NO CHANGES:**
- Say: "No changes to commit in this repository."
- Exit the task

---

## Step 2: Analyze Changes and Generate Title/Message (EXECUTE BASH)

Get list of modified files:
```bash
# Get modified files (staged and unstaged)
git status --short | grep "^[ MARC]" | cut -c4-
```

Determine the type of changes:
- If scripts changed → "Fix:" or "Update:" or "Refactor:"
- If PRD/documentation → "Docs:"
- If configuration → "Config:"

Generate automatic title and message:
```bash
# Count files by type
SCRIPT_COUNT=$(git status --short | grep "\.sh$" | wc -l)
MD_COUNT=$(git status --short | grep "\.md$" | wc -l)
YML_COUNT=$(git status --short | grep -E "\.(yml|yaml|json)$" | wc -l)

# Generate title
if [ "$SCRIPT_COUNT" -gt 0 ]; then
  TITLE="Update"
  MESSAGE="Modified $SCRIPT_COUNT script(s)"
elif [ "$MD_COUNT" -gt 0 ]; then  
  TITLE="Docs"
  MESSAGE="Updated documentation"
else
  TITLE="Chore"
  MESSAGE="Updated files"
fi
```

---

## Step 3: Execute Commit (EXECUTE BASH COMMANDS)

```bash
# Stage all changes
git add -A

# Get current branch name
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Get list of changed files for message
FILES_CHANGED=$(git status --short | grep "^[ MARC]" | cut -c4- | tr '\n' ',' | sed 's/,$//')

# Generate descriptive message
if [ -n "$FILES_CHANGED" ]; then
  MESSAGE="$MESSAGE - $FILES_CHANGED"
fi

# Commit
git commit -m "$TITLE: $MESSAGE"

echo "Committed: $TITLE: $MESSAGE"
```

---

## Step 4: Force Push to Remote (EXECUTE BASH COMMANDS)

```bash
# Check if remote exists
if git remote -v | grep -q origin; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
  git push -f origin "$BRANCH"
  echo "SUCCESS: Force pushed to remote with clean history"
else
  echo "ERROR: No remote configured - committed locally"
fi
```

---

## Important Notes

1. **Auto-detection**: Analyzes which files were modified
2. **Title Categories**:
   - Scripts (.sh) → "Update"
   - Documentation (.md) → "Docs"  
   - Config files → "Chore"
3. **Force Push**: Uses `-f` to rewrite history to a single commit
4. **No arguments needed**: Just type `/review`

---

## Usage

Simply type:
```sh
/review
```

The system will automatically analyze changes and create appropriate title and message.
