> ## Documentation Index
> Fetch the complete documentation index at: https://docs.liquid.ai/llms.txt
> Use this file to discover all available pages before exploring further.

# Configuration

> Configuration commands and file format for the LEAP Bundle CLI

## `config`

View CLI configuration settings.

```sh  theme={"theme":{"light":"github-light","dark":"github-dark"}}
leap-bundle config
```

**Behavior**

* Displays current configuration and config file location
* Configuration is stored in `~/.liquid-leap`

**Examples**

```sh  theme={"theme":{"light":"github-light","dark":"github-dark"}}
# View current configuration
leap-bundle config

# Example output
ℹ Config file location: /home/user/.liquid-leap

Current configuration:
  server_url: https://leap.liquid.ai
```

## Configuration File

The CLI tool stores configuration in `~/.liquid-leap` as a YAML file:

```yaml  theme={"theme":{"light":"github-light","dark":"github-dark"}}
version: 1
api_token: 'your_encrypted_token_here'
server_url: 'https://leap.liquid.ai'
```

**Location:** The file is always stored in the user's home directory as `.liquid-leap`.
