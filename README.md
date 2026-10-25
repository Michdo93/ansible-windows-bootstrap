# ansible-windows-bootstrap

Prepare a Windows host for remote administration with Ansible. The bootstrap creates a local administrator account, installs and enables OpenSSH Server, configures WinRM, and installs the Windows updater script.

## Requirements

- Windows PowerShell 5.1 or later.
- Run bootstrap from an elevated PowerShell session.
- Internet access to download the OpenSSH Windows capability, the updater script, and (when updating) packages from Microsoft/WinGet sources.

## Bootstrap

The script accepts the username and password as parameters. It also prompts for either value if omitted.

Download the script, inspect it, then run:

```powershell
.ootstrap.ps1 -Username sysadmin -Password 'change-this-password'
```

For a prompted password, omit `-Password`:

```powershell
.ootstrap.ps1 -Username sysadmin
```

### Run directly from GitHub

In an elevated PowerShell session, you can download and invoke the script as a ScriptBlock. Pass parameters after the ScriptBlock expression:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Michdo93/ansible-windows-bootstrap/main/bootstrap.ps1'))) -Username 'sysadmin' -Password 'change-this-password'
```

To let the script prompt for the password, omit `-Password`:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Michdo93/ansible-windows-bootstrap/main/bootstrap.ps1'))) -Username 'sysadmin'
```

This is the PowerShell equivalent of downloading and running a script in one command. Unlike piping directly to `iex`, the ScriptBlock form lets you pass the script's parameters. Review the script before running it with administrator privileges. A password supplied on the command line may be visible in shell history and process inspection; omitting it uses the secure prompt.

A password passed on the command line can be visible in shell history and process inspection. Use a unique credential and remove it from shell history after use, or let the script prompt.

The bootstrap:

- Creates or updates and enables the local account, then adds it to the built-in Administrators group.
- Installs the Windows OpenSSH Server capability, sets the `sshd` service to Automatic, starts it, and enables inbound TCP 22.
- Enables WinRM with its service set to Automatic for Ansible Windows modules.
- Downloads `upgrader.ps1` to `C:\ProgramData\Ansible\upgrader.ps1`.

Connect with SSH using the local administrator account:

```sh
ssh sysadmin@HOSTNAME_OR_IP
```

The account receives administrator permissions. Restrict TCP 22 and WinRM TCP 5985 to trusted management hosts or networks. Do not expose them directly to the public Internet.

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

The Windows modules continue to use WinRM. Install the collection on the Ansible controller:

```sh
ansible-galaxy collection install ansible.windows
```

Example inventory using WinRM:

```ini
[windows]
win01 ansible_host=192.168.0.50

[windows:vars]
ansible_connection=winrm
ansible_port=5985
ansible_user=win01\sysadmin
ansible_password=REPLACE_WITH_A_SECRET
ansible_winrm_transport=ntlm
```

Keep the password in Ansible Vault or another secrets manager. WinRM HTTP with NTLM encrypts message contents, but TCP 5985 should be limited to trusted management sources. For public or untrusted networks, use WinRM HTTPS with a valid certificate.

SSH is enabled for shell access and SSH-based automation. The supplied local account is an Administrator, which is required for the updater's system-wide operations. Use Ansible's Windows modules over WinRM where supported.

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
