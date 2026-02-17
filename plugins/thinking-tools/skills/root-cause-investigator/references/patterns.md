# Common Root Cause Patterns

## Configuration Issues
- **Symptoms**: Works locally, fails in production
- **Investigation**: Compare environment configs
- **Root causes**: Missing env vars, wrong paths, permission issues

## Race Conditions
- **Symptoms**: Intermittent failures, timing-dependent bugs
- **Investigation**: Run with race detector, check concurrent access
- **Root causes**: Shared state without synchronization

## Resource Exhaustion
- **Symptoms**: Gradual degradation, OOM errors
- **Investigation**: Monitor memory/CPU usage, check for leaks
- **Root causes**: Unclosed resources, unbounded growth

## Integration Failures
- **Symptoms**: API errors, connection timeouts
- **Investigation**: Check network connectivity, API changes
- **Root causes**: Breaking API changes, network issues, auth problems

## Build/Deployment Issues
- **Symptoms**: Build failures, missing dependencies
- **Investigation**: Check build logs, dependency versions
- **Root causes**: Version mismatches, missing build steps

## Multiple Perspective Analysis

### Technical Implementation
- Code bugs or logic errors
- Missing error handling
- Incorrect assumptions

### Configuration/Environment
- Environment differences
- Missing configuration
- Permission issues

### System Architecture
- Design limitations
- Scalability issues
- Component coupling

### External Dependencies
- Third-party service issues
- API breaking changes
- Network problems

### Process/Workflow
- Missing validation
- Incorrect deployment order
- Documentation gaps
