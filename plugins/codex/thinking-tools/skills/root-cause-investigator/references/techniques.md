# Investigation Techniques

## Error Analysis

```bash
# check recent logs
tail -f /var/log/app.log
journalctl -u service-name -f

# search for error patterns
rg "ERROR|FATAL|Exception|panic|error|fail" logs/

# check build logs (adapt to project language)
# go: go build -v 2>&1 | tee build.log
# node: npm run build --verbose
# python: python -m py_compile file.py
```

## Code Investigation

```bash
# find recent changes
git log --oneline -20
git diff HEAD~5

# check specific error location
git blame file | grep -C 5 "error line"

# search for similar patterns
rg "similar_function" -A 5 -B 5
```

## Dependency Analysis

```bash
# check dependency graph (adapt to project)
# go: go mod graph / go mod why package-name
# node: npm ls / npm why package-name
# python: pip show package-name

# check for version conflicts
# go: go list -m -versions module-name
# node: npm outdated
# python: pip check
```

## Environment Investigation

```bash
# check environment variables
env | grep APP_
printenv | sort

# verify configuration files
cat config.yaml | grep -v "^#"

# check system resources
df -h
free -m
ps aux | grep process-name
```

## Quick Reference Commands

```bash
# recent errors in logs
rg "ERROR|PANIC|FATAL" --sort modified

# find when code was changed
git log -p -S "problematic_code"

# system diagnostics
lsof -p PID        # open files
strace -p PID      # system calls (Linux)
netstat -an | grep LISTEN  # open ports
```
