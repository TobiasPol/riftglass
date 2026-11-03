# Security Policy

Please report vulnerabilities privately via GitHub's "Report a vulnerability" (Security tab) rather than
in a public issue. Relevant areas: handling of the LCU auth token, TLS validation against Riot's local
certificate (`LocalTrustEvaluator`), the update pipeline (Sparkle EdDSA signatures) and anything that
could modify rune pages or item sets that Riftglass does not own.
