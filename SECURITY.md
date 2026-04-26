# Security Notes

## Secrets

Runtime provider keys stay in Supabase Edge Function secrets. The iOS app only
contains the Supabase URL and anon key. Do not commit `.env`,
`Configuration.swift`, private keys, certificates, provisioning profiles, or API
keys.

## Storage Boundaries

All user-controlled Supabase Storage object names must pass server-side owner
and traversal validation before `download`, `upload`, or signed URL creation.
Valid object names are scoped to the authenticated user's UUID prefix and reject
absolute paths, `..`, duplicate separators, backslashes, and unexpected
characters.

## Auth And Data Access

Client requests authenticate with Supabase Auth. Edge Functions re-check row
ownership before reading sessions, chats, folders, handwriting samples, video
jobs, or storage paths. Database migrations define RLS policies for user-owned
tables and storage buckets.

## Dependency Monitoring

The Swift Package Manager lockfile is committed at
`ios/NoWork.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
so dependency scanners can resolve exact package versions. Update dependencies
through Xcode or SwiftPM and commit the updated lockfile.

## Voice

Do not return third-party API keys to the client. Voice transcription uses local
iOS Speech recognition. Gradium text-to-speech is proxied by the authenticated
`voice-token` Edge Function so the `GRADIUM_API_KEY` remains server-side.

## Reporting

Report security issues privately to the repository owner. Rotate affected
provider keys immediately after any suspected exposure and redeploy the relevant
Supabase Edge Functions.
