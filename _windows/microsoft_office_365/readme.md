
# Microsoft 365 Apps — Preparing the XML for Customized Deployments

This document explains how to prepare the Office Deployment Tool (ODT) configuration XML files used to create customised deployments of Microsoft 365 Apps (Office).

Overview
-
This folder contains example XML templates used by the Office Deployment Tool (`setup.exe`) to download and/or install Microsoft 365 Apps with customised settings (channel, edition, product, language, excluded apps, update behaviour, display options, and properties).

Files in this folder should be named to make their intent clear. Recommended filename convention:

- `<arch>_<product>_<channel>.xml`
- Example: `x64_enterprise_current.xml` or `x64_enterprise_semi-annual.xml`

Quick workflow
-
1. Edit one of the example XML templates below (or create a new one) to match your desired configuration.
2. Use the Office Deployment Tool to download source files: `setup.exe /download <your-config>.xml`.
3. Use the Office Deployment Tool to configure/install: `setup.exe /configure <your-config>.xml`.

Minimal example
-
This is a minimal configuration that installs the 64-bit Microsoft 365 Apps for enterprise on the Current channel in `en-US` and silently accepts the EULA.

```xml
<Configuration>
	<Add OfficeClientEdition="64" Channel="Current">
		<Product ID="O365ProPlusRetail">
			<Language ID="en-us" />
		</Product>
	</Add>
	<Display Level="None" AcceptEULA="TRUE" />
</Configuration>
```

Common customisations
-
- OfficeClientEdition — `32` or `64` (choose according to your architecture).
- Channel — release channel: `Current`, `MonthlyEnterprise`, `Broad`, `SemiAnnual`, `Targeted` (use the channel names your environment requires).
- Product ID — common values: `O365ProPlusRetail` (Microsoft 365 Apps for enterprise), `O365BusinessRetail` (business SKU). Confirm for your licensing.
- Language — specify language with the `Language` element (e.g. `en-us`, `en-gb`, `fr-fr`).
- ExcludeApp — remove unwanted applications to reduce footprint (e.g. `Lync`, `Access`, `Publisher`, `OneNote`).
- Updates — control update behaviour with the `Updates` element (Enabled, Channel attribute, etc.).
- Display — set `Level` to `None` for silent installs; `Full` to show UI; set `AcceptEULA` to `TRUE` if running unattended.
- Property — set properties like `AUTOACTIVATE` or other supported ODT properties.

Example — enterprise build with exclusions and updates
-
```xml
<Configuration>
	<Add OfficeClientEdition="64" Channel="MonthlyEnterprise">
		<Product ID="O365ProPlusRetail">
			<Language ID="en-us" />
			<ExcludeApp ID="Lync" />
			<ExcludeApp ID="Publisher" />
		</Product>
	</Add>
	<Updates Enabled="TRUE" Channel="MonthlyEnterprise" />
	<Display Level="None" AcceptEULA="TRUE" />
	<Property Name="AUTOACTIVATE" Value="1" />
</Configuration>
```

Offline / Download + deploy
-
To prepare an offline source you first download the files (on a machine with internet):

```powershell
# from the folder containing setup.exe (Office Deployment Tool)
\setup.exe /download x64_enterprise_current.xml
```

This creates the Office source files in the same folder (or a folder specified in the XML). After downloading you can distribute the folder with the `setup.exe` and the chosen XML and run:

```powershell
\setup.exe /configure x64_enterprise_current.xml
```

Filename and folder recommendations
-
- Keep templates in this folder (e.g. `_windows/microsoft_office_365/`) and name them with architecture, product and channel to avoid confusion.
- If you maintain multiple channels or architectures, create a subfolder per architecture (e.g. `x64_enterprise_current/`) and place the XML and any supporting scripts there.
- Include a short accompanying `.ps1` or `.cmd` that wraps the `setup.exe /configure` invocation if you need consistent parameters across deployments.

Validation and testing
-
- Always test your XML in a lab VM before wide deployment.
- Use `Display Level="Full"` for interactive testing so you can observe progress and errors.
- Check `setup.exe` exit codes and the `%temp%` logs for failures when running unattended.

Common pitfalls
-
- Channel/Version mismatch: specifying a Channel that the setup can't resolve will fail to download; use allowed channel names.
- Product ID mismatch: ensure the `Product ID` matches your licensing.
- Architecture mismatch: don't select OfficeClientEdition `64` for 32-bit systems.
- Permissions: running `setup.exe` with insufficient privileges can cause silent failures; run with administrative rights where required.

References and support
-
- Use the Office Deployment Tool bundled `setup.exe` for download and configure operations.
- Keep your configuration templates under version control and document changes made for each channel.

If you'd like, I can:
- add concrete example templates into `x64_enterprise_current/` and `x64_enterprise_semi-annual/` folders,
- or validate a specific XML you plan to use.

