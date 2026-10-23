# ================================================================================
# FILE: acm.tf
# ================================================================================
#
# Purpose:
#   Generate a self-signed TLS certificate and import it into ACM so the
#   Application Load Balancer can terminate HTTPS without a registered
#   domain or a public certificate authority.
#
# Why HTTPS is required rather than optional:
#   Over plain HTTP, carrier and ISP security products inspect page content
#   inline. In practice they classify an unbranded credential form on an
#   *.elb.amazonaws.com hostname as phishing and block it outright, and some
#   mobile carriers also mangle the WebSocket Upgrade handshake that
#   code-server depends on. TLS ends both behaviours — the middlebox can no
#   longer read or rewrite the stream.
#
# Trade-off:
#   Browsers do not trust a self-signed issuer, so users get an interstitial
#   warning and must choose "Advanced -> Proceed". The certificate's common
#   name is set to the ALB's own DNS name, so the warning covers only the
#   untrusted issuer, not a hostname mismatch.
#
#   To eliminate the warning entirely, replace this file with a DNS-validated
#   ACM certificate for a domain in Route 53 and point an alias record at the
#   ALB.
#
# ================================================================================


# ================================================================================
# SECTION: Provider Requirement - TLS
# ================================================================================

# The tls provider generates the key and certificate locally at plan time.
# No external tooling (openssl) is invoked, so apply.sh gains no dependency.
terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}


# ================================================================================
# SECTION: Private Key
# ================================================================================

resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}


# ================================================================================
# SECTION: Self-Signed Certificate
# ================================================================================

# The common name is the ALB's generated DNS name. The ALB does not depend on
# the certificate, so this ordering resolves cleanly:
#   aws_lb -> tls_self_signed_cert -> aws_acm_certificate -> https listener
resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = aws_lb.shinyproxy_alb.dns_name
    organization = "ShinyProxy Lab"
  }

  # Matching SAN as well — browsers ignore common_name on its own.
  dns_names = [aws_lb.shinyproxy_alb.dns_name]

  validity_period_hours = 8760 # One year; lab certificate, not renewed.

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}


# ================================================================================
# SECTION: ACM Import
# ================================================================================

# ALB listeners accept any certificate in ACM, including imported ones — a
# public CA is not required. Imported certificates cannot auto-renew, which
# is acceptable for a lab that is torn down regularly.
resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem

  # Replace before removing so the listener is never left without a cert.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "shinyproxy-eks-alb-self-signed"
  }
}


# ================================================================================
# SECTION: Outputs
# ================================================================================

output "shinyproxy_url" {
  description = "HTTPS endpoint for ShinyProxy"
  value       = "https://${aws_lb.shinyproxy_alb.dns_name}"
}

# Emitted so the certificate can be added to a workstation's trust store
# without digging it out of the browser. Trusting it is required for VS Code
# webviews — Chrome refuses to register a service worker behind an untrusted
# certificate, and webviews are built on one. Public half only; the private
# key stays in state.
output "alb_certificate_pem" {
  description = "Self-signed certificate to trust on client machines"
  value       = tls_self_signed_cert.alb.cert_pem
}
