# Contributing to Server Security Toolkit

Thank you for your interest in contributing to Server Security Toolkit! This document provides guidelines and instructions for contributing to the project.

## 🌟 Ways to Contribute

- **Report Bugs**: Found a bug? Open an issue with detailed reproduction steps
- **Suggest Features**: Have an idea? Create a feature request issue
- **Improve Documentation**: Help make our docs clearer and more comprehensive
- **Submit Code**: Fix bugs or implement new features via pull requests
- **Test**: Try the toolkit on different systems and report your findings
- **Translate**: Help translate documentation to other languages

## 🐛 Reporting Issues

When reporting issues, please include:

1. **System Information**:
   - OS and version (e.g., Ubuntu 22.04, Debian 12)
   - Bash version: `bash --version`
   - Installed toolkit version

2. **Description**:
   - Clear description of the issue
   - Expected behavior vs actual behavior
   - Steps to reproduce

3. **Logs**:
   - Relevant logs from `/var/log/server-security-toolkit/security-toolkit.log`
   - Error messages (with sensitive data redacted)

4. **Context**:
   - What were you trying to accomplish?
   - Any recent system changes?

### Issue Template

```markdown
**System Information:**
- OS: Ubuntu 22.04 LTS
- Toolkit Version: v2.0.0
- Bash Version: 5.1.16

**Description:**
Brief description of the issue

**Steps to Reproduce:**
1. Step one
2. Step two
3. Step three

**Expected Behavior:**
What should happen

**Actual Behavior:**
What actually happened

**Logs:**
```
[paste relevant logs here]
```

**Additional Context:**
Any other relevant information
```

## 💡 Suggesting Features

Before suggesting a feature:
1. Check if it's already been requested in Issues
2. Consider if it fits the project's scope (server security automation)
3. Think about backward compatibility

Feature requests should include:
- **Use Case**: What problem does this solve?
- **Proposed Solution**: How would it work?
- **Alternatives**: Other approaches you've considered
- **Impact**: Who would benefit from this feature?

## 🔧 Development Setup

### Prerequisites

- Ubuntu 20.04+ or Debian 12+ (for testing)
- Git
- Bash 4.0+
- shellcheck (for linting)
- Basic understanding of:
  - Bash scripting
  - Linux system administration
  - SSH and firewall configuration

### Getting Started

1. **Fork the repository**
   ```bash
   # Fork via GitHub UI, then clone your fork
   git clone https://github.com/YOUR_USERNAME/server-security-toolkit.git
   cd server-security-toolkit
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-description
   ```

3. **Make your changes**
   - Follow the coding standards (see below)
   - Test thoroughly
   - Update documentation as needed

4. **Run quality checks**
   ```bash
   # Lint all scripts
   shellcheck main.sh modules/*.sh tests/*.sh
   
   # Run smoke tests
   cd tests
   sudo ./smoke_test.sh
   ```

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add new feature description"
   # or
   git commit -m "fix: resolve issue description"
   ```

6. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   # Create Pull Request via GitHub UI
   ```

## 📝 Coding Standards

### Bash Script Guidelines

1. **Shebang and Options**
   ```bash
   #!/bin/bash
   # Use strict mode
   set -euo pipefail
   ```

2. **Function Naming**
   - Use lowercase with underscores: `function_name()`
   - Descriptive names: `backup_ssh_config()` not `bsc()`

3. **Variable Naming**
   - Local variables: lowercase with underscores
   - Global/readonly variables: UPPERCASE
   - Use `local` keyword in functions
   ```bash
   readonly INSTALL_DIR="/opt/security-toolkit"
   local backup_file="config.backup"
   ```

4. **Error Handling**
   - Always check command exit codes for critical operations
   - Use logging functions: `log_error`, `log_warning`, `log_info`, `log_success`
   - Provide helpful error messages
   ```bash
   if ! systemctl restart ssh; then
       log_error "Failed to restart SSH service"
       return 1
   fi
   ```

5. **User Input Validation**
   - Always validate user input
   - Provide clear prompts
   - Handle edge cases
   ```bash
   while true; do
       read -p "Enter port (1024-65535): " -r port
       if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1024 ]]; then
           log_error "Invalid port"
           continue
       fi
       break
   done
   ```

6. **Security Considerations**
   - Never log sensitive data (passwords, keys)
   - Create backups before destructive operations
   - Use quotes around variables: `"$variable"` not `$variable`
   - Avoid command injection: use arrays for command arguments
   ```bash
   # Good
   local cmd=("systemctl" "restart" "$service")
   "${cmd[@]}"
   
   # Bad - potential injection
   systemctl restart $service
   ```

7. **Documentation**
   - Add comments for complex logic
   - Use function headers for clarity
   ```bash
   # Backup SSH configuration to timestamped file
   # Returns: 0 on success, 1 on failure
   backup_ssh_config() {
       # Function implementation
   }
   ```

### Module Structure

Each module should:
1. Start with a comment describing its purpose
2. Define module-specific functions
3. Provide a main entry function for the menu
4. Handle errors gracefully
5. Log all significant operations

Example:
```bash
#!/bin/bash
# SSH Security Module - Handles SSH configuration and key management

# Backup SSH configuration
backup_ssh_config() {
    # Implementation
}

# Main module entry point
configure_ssh_security() {
    while true; do
        # Menu implementation
    done
}
```

## 🧪 Testing Requirements

All contributions must:

1. **Pass shellcheck**
   ```bash
   shellcheck -x main.sh modules/*.sh tests/*.sh
   ```

2. **Run smoke tests**
   ```bash
   cd tests && sudo ./smoke_test.sh
   ```

3. **Test on target systems**
   - Ubuntu 20.04 LTS
   - Ubuntu 22.04 LTS
   - Debian 12 (Bookworm)

4. **Test edge cases**
   - Empty inputs
   - Invalid inputs
   - Existing configurations
   - Permission issues

5. **Verify backups work**
   - Test restore functionality
   - Ensure no data loss

## 📋 Pull Request Guidelines

### PR Title Format

Use conventional commits format:
- `feat: add new feature`
- `fix: resolve bug`
- `docs: update documentation`
- `test: add tests`
- `refactor: code improvement`
- `chore: maintenance tasks`

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing functionality to break)
- [ ] Documentation update

## Testing
- [ ] Passed shellcheck
- [ ] Ran smoke tests
- [ ] Tested on Ubuntu 22.04
- [ ] Tested on Debian 12
- [ ] Tested edge cases

## Checklist
- [ ] My code follows the project's coding standards
- [ ] I have commented complex code sections
- [ ] I have updated documentation as needed
- [ ] I have added/updated tests
- [ ] All tests pass
- [ ] I have checked for security implications

## Screenshots (if applicable)
Add screenshots showing the feature/fix in action

## Related Issues
Fixes #(issue number)
```

### Review Process

1. Automated checks must pass (shellcheck, basic tests)
2. At least one maintainer approval required
3. All review comments must be addressed
4. No merge conflicts
5. Documentation updated if needed

## 🔐 Security Guidelines

### Reporting Security Issues

**DO NOT** open public issues for security vulnerabilities.

Instead:
1. Email security concerns to the maintainers
2. Include detailed description and impact assessment
3. Wait for acknowledgment before public disclosure

### Security Checklist for Contributors

- [ ] No hardcoded passwords or secrets
- [ ] No logging of sensitive data
- [ ] Input validation for all user inputs
- [ ] Backups created before destructive operations
- [ ] Proper error handling to prevent information leakage
- [ ] Secure defaults (principle of least privilege)
- [ ] No command injection vulnerabilities
- [ ] File permissions set correctly

## 📚 Resources

### Learning Resources

- [Bash Guide](https://mywiki.wooledge.org/BashGuide)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

### Useful Tools

- **shellcheck**: Bash linter
  ```bash
  sudo apt install shellcheck
  ```

- **shfmt**: Bash formatter
  ```bash
  sudo apt install shfmt
  ```

## 🎉 Recognition

Contributors will be:
- Listed in project README
- Credited in release notes
- Recognized in commit history

## 📞 Getting Help

- **Questions**: Open a Discussion on GitHub
- **Chat**: Join our community (if available)
- **Issues**: Use GitHub Issues for bugs/features

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to Server Security Toolkit! Your efforts help make server security accessible to everyone. 🛡️
