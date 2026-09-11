# Targeted apply only — not used by default cluster deploy.
# Agent steps: clusters/virt/AGENTS.md → Step 6b (External VM ↔ bastion BGP test).
# Also applies worker SG rules when enable_route_server=true in main tfvars.

enable_bastion         = true
bastion_enable_bgp_e2e = true
bastion_public_ip      = false
