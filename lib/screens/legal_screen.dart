import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';

enum LegalDoc { privacy, terms, guidelines }

/// In-app legal & safety documents required for Google Play compliance and
/// transparent user consent. Works fully offline and links to external URLs
/// when configured via dart-defines.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(doc);
    final theme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(spec.title)),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 680,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    Icon(spec.icon, color: AppColors.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(spec.subtitle, style: theme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            'Effective ${spec.updatedAt} · ${AppInfo.name}',
                            style: theme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              for (final section in spec.sections) ...[
                Text(
                  section.heading,
                  style: theme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  section.body,
                  style: theme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (Validators.isSafeHttpsUrl(spec.externalUrl)) ...[
                const Divider(height: 1, color: AppColors.hairline),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(spec.externalUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Open web version'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DocSpec {
  const _DocSpec({
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    required this.icon,
    required this.externalUrl,
    required this.sections,
  });

  final String title;
  final String subtitle;
  final String updatedAt;
  final IconData icon;
  final String externalUrl;
  final List<({String heading, String body})> sections;
}

_DocSpec _specFor(LegalDoc doc) => switch (doc) {
      LegalDoc.privacy => _DocSpec(
          title: 'Privacy Policy',
          subtitle: 'How PhotoSpot handles your data',
          updatedAt: 'Nov 2026',
          icon: Icons.privacy_tip_outlined,
          externalUrl: AppInfo.privacyPolicyUrl,
          sections: [
            (
              heading: '1. Data we collect',
              body:
                  '• Account details: When you create an account, we store your email address, display name, optional bio, home city, and optional avatar.\n'
                  '• Location: Requested only when you tap location actions or place a spot. Used to center the map, sort nearby places, and compute distances.\n'
                  '• Photos & metadata: When you pick a photo to publish, PhotoSpot reads GPS coordinates locally on your device to pre-fill the pin, then strips EXIF/XMP metadata before uploading the compressed image.',
            ),
            (
              heading: '2. Personalization & local storage',
              body:
                  'Your saves, likes, view history, and blocked users are stored locally on your device (and synced to your account when signed in). You can turn off feed personalization or clear view history anytime in Settings.',
            ),
            (
              heading: '3. Third-party services',
              body:
                  '• Supabase: Hosts community spots, comments, profiles, and uploaded spot photos when configured.\n'
                  '• Map tiles & geocoding: Basemap tiles and place searches are requested from OpenStreetMap, Esri, CARTO (if enabled), Photon, and Nominatim.',
            ),
            (
              heading: '4. Your rights & deletion',
              body:
                  'You can export a summary of your data, delete individual spots or comments you posted, or permanently delete your account and associated data directly from Settings → Data & Privacy, or by contacting ${AppInfo.supportEmail}.',
            ),
          ],
        ),
      LegalDoc.terms => _DocSpec(
          title: 'Terms of Service',
          subtitle: 'Rules for using PhotoSpot',
          updatedAt: 'Nov 2026',
          icon: Icons.gavel_rounded,
          externalUrl: AppInfo.termsUrl,
          sections: [
            (
              heading: '1. Eligibility & accounts',
              body:
                  'You must be at least 13 years old (or the minimum digital consent age in your country) to create an account. You are responsible for keeping your login credentials secure.',
            ),
            (
              heading: '2. Content you share',
              body:
                  'You retain ownership of photos and descriptions you publish. By publishing a spot or comment, you grant PhotoSpot a non-exclusive license to display that content to other users of the service. Only upload photos you took or have permission to share.',
            ),
            (
              heading: '3. Safety & real-world responsibility',
              body:
                  'Photo spots are shared by the community. Always verify local access rules, opening hours, weather, and terrain before visiting any location. Never trespass on private property or take unsafe risks for a photograph.',
            ),
            (
              heading: '4. Moderation & enforcement',
              body:
                  'We may remove content or suspend accounts that violate our Community Guidelines, infringe intellectual property, or endanger people or protected environments.',
            ),
            (
              heading: '5. Contact',
              body:
                  'Questions, copyright notices, or takedown requests can be sent to ${AppInfo.supportEmail}.',
            ),
          ],
        ),
      LegalDoc.guidelines => const _DocSpec(
          title: 'Community Guidelines',
          subtitle: 'Keep the map helpful and respectful',
          updatedAt: 'Nov 2026',
          icon: Icons.shield_outlined,
          externalUrl: '',
          sections: [
            (
              heading: '1. Share real, accessible places',
              body:
                  'Pin locations that are genuinely open to the public. Do not publish private residences, restricted areas, or dangerous cliff/rooftop access.',
            ),
            (
              heading: '2. Protect fragile nature & local communities',
              body:
                  'Follow Leave No Trace principles. Avoid posting exact coordinates for vulnerable wildlife habitats or overcrowded residential spots.',
            ),
            (
              heading: '3. Be respectful in comments',
              body:
                  'Share helpful photography tips — light, timing, lenses, and access notes. Harassment, hate speech, spam, and explicit content are prohibited and can be reported or blocked directly from any spot or comment.',
            ),
          ],
        ),
    };
