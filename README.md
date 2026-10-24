# ansible-windows-bootstrap

Bootstrap a Windows host for remote management with Ansible over WinRM, and install a non-interactive Windows/software updater script for Ansible to execute later.

## Features

- Prompts for a local automation username and password without echoing the password.
- Creates the local account, or updates and enables it if it already exists.
- Adds the account to the local **Administrators** group.
- Enables WinRM and configures the service to start automatically.
- Uses WinRM over HTTP with NTLM/Negotiate message encryption; does not enable Basic authentication or unencrypted WinRM traffic.
- Enables the Windows Remote Management firewall rule.
- Configures the Windows local-account remote token policy required by some WinRM local-administrator setups.
- Downloads `upgrader.ps1` to `%ProgramData%\Ansible\upgrader.ps1`.
- The upgrader is designed for non-interactive execution: no GUI restart prompt and no `pause`.

## Requirements

- Windows PowerShell 5.1 or later.
- Run the bootstrap in an **elevated PowerShell session** (Run as administrator).
- Network access to GitHub and, when updating, Microsoft/WinGet package sources.
- Supported Windows versions must include the PowerShell cmdlets used by the script (`Get-LocalUser`, `New-LocalUser`, and `Get-LocalGroupMember`).

## Quick start

Open **PowerShell as Administrator**, then run:

```powershell
irm https://raw.githubusercontent.com/Michdo93/ansible-windows-bootstrap/main/bootstrap.ps1 | iex
```

The script asks for the local account name, password, and password confirmation. The password is read as a `SecureString`; it is not passed as a command-line argument or written to the script.

> Review the script before piping a remote script into `iex`. For production, pin the URL to a reviewed commit or download and inspect the script first. This command executes the current contents of the `main` branch with administrator privileges.

## What gets configured?

### Local account

The account is a local Windows account and is added to the built-in Administrators group. This is required for general system maintenance and installing Windows updates. Treat the credentials as privileged secrets.

### WinRM

The bootstrap enables PowerShell remoting and the standard WinRM HTTP listener on TCP port 5985. It disables Basic authentication and keeps `AllowUnencrypted` disabled.

NTLM/Negotiate encrypts WinRM message contents even when the transport is HTTP, but the listener should still be restricted to trusted management hosts/subnets. For untrusted networks, configure WinRM over HTTPS (TCP 5986) with a valid certificate and suitable firewall rules. Do not expose WinRM directly to the public Internet.

## Installed updater

The bootstrap downloads the updater from:

`https://raw.githubusercontent.com/Michdo93/ansible-windows-bootstrap/main/upgrader.ps1`

Default install path:

`C:\ProgramData\Ansible\upgrader.ps1`

The script attempts to update applications with WinGet and Windows/Microsoft updates with the `PSWindowsUpdate` module. It is intended for unattended use and does not show a GUI dialog or wait for keyboard input.

Run it from an elevated PowerShell session:

```powershell
& "$env:ProgramData\Ansible\upgrader.ps1"
```

To allow it to reboot the host when a reboot is pending:

```powershell
& "$env:ProgramData\Ansible\upgrader.ps1" -RebootIfRequired
```

To skip one update mechanism:

```powershell
& "$env:ProgramData\Ansible\upgrader.ps1" -SkipWinget
& "$env:ProgramData\Ansible\upgrader.ps1" -SkipWindowsUpdate
```

WinGet availability and behavior can vary by Windows edition, user context, package source, and installed applications. Driver delivery also depends on the drivers made available by Windows Update and the device vendor.

## Ansible inventory example

Install the `ansible.windows` collection on the Ansible controller:

```bash
ansible-galaxy collection install ansible.windows
```

Example inventory for a local account using NTLM:

```ini
[windows]
win01 ansible_host=192.168.0.50

[windows:vars]
ansible_connection=winrm
ansible_port=5985
ansible_user=win01\\ansible
ansible_password=REPLACE_WITH_A_SECRET
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
```

Use Ansible Vault or another secrets manager for `ansible_password`; do not commit real credentials to the inventory. The certificate-validation setting shown is typically relevant to HTTPS configurations and can be omitted for this HTTP example.

Test connectivity:

```bash
ansible windows -i inventory.ini -m ansible.windows.win_ping
```

Execute the installed updater:

```yaml
---
- name: Update Windows hosts
  hosts: windows
  tasks:
    - name: Run the Windows updater
      ansible.windows.win_powershell:
        script: |
          & "$env:ProgramData\Ansible\upgrader.ps1"
      register: update_result
```

Plan reboots explicitly in Ansible. Do not pass `-RebootIfRequired` unless a reboot during the playbook run is acceptable.

## Security notes

- The automation account is a local administrator. Anyone who obtains its credentials can administer the host.
- `LocalAccountTokenFilterPolicy=1` relaxes remote UAC token filtering for local accounts. This has security implications; restrict WinRM to trusted management hosts/subnets and use a dedicated credential.
- Restrict TCP 5985 to the Ansible controller or trusted management subnet.
- Prefer a dedicated automation secret per host or a managed secret solution; avoid shared default passwords.
- For production networks, prefer WinRM HTTPS with certificate validation.
- Inspect scripts downloaded from GitHub before running them with administrator privileges.
- The bootstrap installs the updater from the repository's `main` branch by default. Pin a reviewed commit if you require reproducible deployments.

## Repository layout

```text
ansible-windows-bootstrap/
├── bootstrap.ps1
├── upgrader.ps1
└── README.md
```

## License

Choose and add a license before redistributing or modifying this repository.
