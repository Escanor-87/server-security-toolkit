# Changelog

All notable changes to Server Security Toolkit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- LICENSE file (MIT License)
- Unified `get_ssh_port()` function in main.sh for consistent SSH port detection across all modules
- Port availability validation via `is_port_available()` function before SSH port changes
- Network timeout protection for git operations (30s for fetch, 60s for clone)
- Enhanced .gitignore patterns for better coverage of backups, IDE files, and temporary files
- Comprehensive CHANGELOG.md for tracking project changes
- CONTRIBUTING.md with guidelines for contributors
- Extended smoke_test.sh with more comprehensive validation

### Fixed
- **CRITICAL**: Race condition in UFW rules update - now adds new SSH port rule BEFORE removing old one
- SSH port detection inconsistencies across firewall.sh and system_hardening.sh modules
- Error handling in firewall.sh for backup file rotation (mapfile + find with null-terminated strings)
- Git clone/fetch operations now have proper timeout handling to prevent indefinite hangs
- Improved backup rotation logic to handle edge cases with file paths containing spaces

### Changed
- All modules now use centralized `get_ssh_port()` function instead of local implementations
- UFW rule management now safer during SSH port changes - prevents accidental lockouts
- Install.sh provides better error messages for network connectivity issues
- Backup file patterns in .gitignore now more comprehensive

### Security
- Port availability check prevents SSH from binding to already-occupied ports
- Race condition fix ensures SSH remains accessible during port changes
- Better validation of user input for port numbers

## [2.0.0] - 2025-01-XX

### Added
- Modular architecture with separate modules for SSH, firewall, and system hardening
- Interactive menu system with visual status indicators
- Comprehensive logging system with rotation and filtering
- Backup and restore functionality for all configuration changes
- Support for both Ubuntu 20.04+ and Debian 12+
- One-line installation script
- CLI aliases: `sst` for Security Toolkit and `f2b` for fail2ban
- Automatic UFW rule updates when SSH port changes
- SSH key management (generation, import, export)
- fail2ban integration with journald support
- CrowdSec support (optional)
- Docker management capabilities
- Color-coded status indicators for services

### Changed
- Complete rewrite from monolithic script to modular architecture
- Improved error handling and user feedback
- Enhanced safety checks before making system changes

### Fixed
- Various stability improvements
- Better handling of edge cases in configuration parsing

## [1.0.0] - Initial Release

### Added
- Basic SSH hardening
- UFW firewall setup
- fail2ban installation
- System update automation

---

## Version History Notes

### Migration from 1.x to 2.x
- 2.x introduces breaking changes with new modular architecture
- Manual migration not required - fresh install recommended
- Existing configurations are preserved through backup system

### Deprecation Notices
- Old `ss` and `security-toolkit` commands replaced with unified `sst` command
- Legacy monolithic script no longer maintained

---

**Legend:**
- `Added` - New features
- `Changed` - Changes in existing functionality
- `Deprecated` - Soon-to-be removed features
- `Removed` - Removed features
- `Fixed` - Bug fixes
- `Security` - Security-related changes
