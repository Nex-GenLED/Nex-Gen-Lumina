<!-- docs_guard: allow-banned -->
# Store listings and website — what to change (not published)

The App Store listing, the Play listing, the data-safety and App Privacy answers, and the website are outside this repository. Export their current text into this folder (one file per page) so the next pass can check it against `docs/FACTS.md`. Until then, apply these rules from the [claims policy](../guides/internal/33-claims-policy.md):

## Remove wherever it appears

- Any mention of Alexa, Google Home or Google Assistant control. Linking has never worked for anyone. (Siri Shortcuts on iPhone and Android app shortcuts may be mentioned.)
- "Download from the App Store / Google Play" calls to action. The app is invitation-only.
- "Lifetime warranty". Use: 5-year product warranty, 1-year labor minimum, 50,000-hour rated life.
- "AR" or "augmented reality".
- "Control from anywhere" without "with the Lumina Bridge your installer installs".
- "Zero maintenance", "set it and forget it".
- "Military-grade", "bank-level", "encrypts everything", "GDPR / CCPA compliant", "SOC 2", "audited", "90-day retention", "export your data", "opt out of analytics".
- OpenAI as the AI vendor (it is Anthropic, through Nex-Gen's own service).
- "10 requests per hour" (the limit is 50).
- Any customer name, testimonial attributed to a named person, or quoted price.

## Play data-safety answers that must change

- Data retention: not "90 days". Profile, schedules, designs and AI usage records are kept until the account is deleted.
- Data shared with third parties: yes. Lumina AI request text goes to Anthropic; hosting is Google Firebase.
- Encryption at rest: only the home address, the home Wi-Fi name and the webhook address are stored encrypted; state that, not "all data".

## Support contact on both listings, the data-safety forms and the website

The support email is general@nex-genled.com, lowercase, everywhere. No other address appears. (Delivery to this address is UNVERIFIED until the owner sends a test.)

## Tester notes (TestFlight "What to Test")

Copy the entry for the build from `docs/guides/internal/31-release-notes.md` and end with "Send reports to general@nex-genled.com with the date and time."

*Facts: T-VA1, T-VA2, T-O8, T-O6, T-R1, T-R9, T-X14, T-X15, T-X16, T-O4, T-SU2.*
