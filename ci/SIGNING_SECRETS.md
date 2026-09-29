# GitHub Actions — signing secrets for a device-installable IPA
#
# Optional. Without these, the workflow still builds an **unsigned** IPA artifact
# (downloadable, but not installable on iPhone until resigned).
#
# Add as repository secrets (Settings → Secrets and variables → Actions):
#
# APPLE_CERTIFICATE_BASE64
#   Base64 of your .p12 distribution/development certificate.
#   openssl base64 -A -in Certificates.p12
#
# APPLE_CERTIFICATE_PASSWORD
#   Password for that .p12 file.
#
# APPLE_PROVISION_PROFILE_BASE64
#   Base64 of the .mobileprovision matching bundle id ar.com.metrogas.demo
#   openssl base64 -A -in profile.mobileprovision
#
# APPLE_TEAM_ID
#   10-character Apple Developer Team ID.
#
# IOS_EXPORT_METHOD (optional)
#   ad-hoc | development | app-store-connect | enterprise
#   Default in workflow: ad-hoc
