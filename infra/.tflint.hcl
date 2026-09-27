config {
  format = "compact"
}

# No provider-specific ruleset plugin here — tflint doesn't ship one for
# hcloud (unlike aws/azurerm/google). The bundled core Terraform-language
# rules (unused declarations, deprecated syntax, etc.) are enabled by
# default with no plugin block needed.
