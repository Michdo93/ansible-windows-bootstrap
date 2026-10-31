# ansible-windows-bootstrap

Prepare a Windows host for remote administration with Ansible. The bootstrap creates a local administrator account, installs and enables OpenSSH Server, configures WinRM, and installs the Windows updater script.

## Requirements

- Windows PowerShell 5.1 or later.
- Run bootstrap from an elevated PowerShell session.
- Internet access to download the OpenSSH Windows capability, the updater script, and (when updating) packages from Microsoft/WinGet sources.

## Bootstrap

Normally [ssh-ansible-bootstrap-manager](https://github.com/Michdo93/ssh-ansible-bootstrap-manager) / [ansible-inventory-generator](https://github.com/Michdo93/ansible-inventory-generator) upload this script over SSH (SFTP) and run it elevated, passing the account name, password and the control node's SSH public key. The password is handed over in a temporary file that is deleted immediately, not on the command line.

Manual run from an elevated PowerShell:

```powershell
.\bootstrap.ps1 -Username ansible -PublicKey 'ssh-ed25519 AAAA... ansible@controlnode'
```

Without `-Password` the script prompts securely (twice). Run directly from GitHub:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Michdo93/ansible-windows-bootstrap/main/bootstrap.ps1'))) -Username 'ansible' -PublicKey 'ssh-ed25519 AAAA...'
```

The bootstrap:

- Creates or updates and enables the local account (password never expires) and adds it to the built-in Administrators group (by SID, works on localized Windows).
- Installs the OpenSSH Server capability, sets `sshd` to Automatic, enables password authentication, opens TCP 22 and sets Windows PowerShell as the default SSH shell.
- Installs `-PublicKey` in `C:\ProgramData\ssh\administrators_authorized_keys` (the file OpenSSH uses for administrators), restricts its ACL to SYSTEM and Administrators, and restores the `Match Group administrators` block in `sshd_config` if it was removed.
- Enables WinRM (Kerberos/Negotiate, no Basic, no unencrypted traffic).
- Downloads `upgrader.ps1` to `C:\ProgramData\Ansible\upgrader.ps1`.

Afterwards the control node logs in without a password:

```sh
ssh ansible@HOSTNAME_OR_IP
```

## Run the updater

The updater requires an elevated Administrator session. After SSH login as the provisioned local administrator, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Ansible\upgrader.ps1
```

To reboot automatically if an update requires it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Ansible\upgrader.ps1 -RebootIfRequired
```

Skip an update mechanism when needed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Ansible\upgrader.ps1 -SkipWinget
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Ansible\upgrader.ps1 -SkipWindowsUpdate
```

The updater installs the `PSWindowsUpdate` PowerShell module and NuGet provider when missing. WinGet application upgrades are attempted when `winget.exe` is available in the account's environment. WinGet may be unavailable in some Windows editions or remote account contexts.

## Ansible

The inventory generator writes for Windows hosts (no password in clear text):

```ini
win01 ansible_host=192.168.0.50 ansible_port=22 ansible_user=ansible
```

`host_vars/win01/vars.yml`:

```yaml
ansible_connection: ssh
ansible_shell_type: powershell
ansible_become_method: runas
ansible_become_user: "ansible"
ansible_become_password: "{{ vault_ansible_become_password }}"
```

`host_vars/win01/vault.yml` is encrypted with `ansible-vault`. SSH authenticates with the key; `runas` with the vaulted password gives tasks a full interactive-equivalent token, which Windows Update and similar APIs require. Run the updater with:

```yaml
- name: Install updates
  ansible.windows.win_powershell:
    script: '& C:\ProgramData\Ansible\upgrader.ps1 -RebootIfRequired'
  become: true
```

Install the collection on the control node: `ansible-galaxy collection install ansible.windows`. WinRM stays enabled if you prefer `ansible_connection: winrm`; keep its password in Ansible Vault as well.

## Security

- The automation account has full local administrator access. Protect its password and any SSH private keys.
- Restrict inbound SSH and WinRM to trusted management sources.
- Review scripts before running them with administrator privileges.
- For repeatable deployments, pin the updater URL to a reviewed commit instead of tracking the repository's `main` branch.

## Repository layout

```text
ansible-windows-bootstrap/
├── bootstrap.ps1
├── upgrader.ps1
└── README.md
```

## License

Choose and add a license before redistributing or modifying this repository.
