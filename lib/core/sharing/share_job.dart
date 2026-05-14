import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../mock/models.dart';

/// Native OS share sheet for a [Job].
///
/// Builds a clean plain-text "card" workers can drop into WhatsApp,
/// Telegram, SMS, email, etc. Plain text is the right format here:
/// it works in every chat app, doesn't require image generation
/// (which would need a server-rendered PNG + CDN), and stays readable
/// even when the receiving app strips formatting.
///
/// Layout (WhatsApp preview at the top, full details below):
///
///   ₦5,000 · Loader · Apapa, Lagos
///
///   Load 5 tons of rebar
///
///   💵 ₦5,000
///   ⏱️  4 hours
///   📍 Owode-Onirin Iron Market, Lagos
///   🏢 Adeolu Iron Wholesale
///   🗓️  Fri, Jul 4 · 3:00 PM
///
///   📍 Open in Maps:
///   https://www.google.com/maps/search/?api=1&query=6.4474,3.3611
///
///   Posted on Forge.
///
/// The Google Maps link uses the universal `search` URL scheme — no
/// API key, no quota. On both iOS and Android the recipient can tap
/// it to open the location directly in their Maps app.
Future<void> shareJob(Job job) async {
  final currency = NumberFormat.currency(
    locale: 'en_NG',
    symbol: '₦',
    decimalDigits: 0,
  );
  final dateFmt = DateFormat('EEE, MMM d · h:mm a');

  final pay = currency.format(job.payAmount);
  final mapsUrl =
      'https://www.google.com/maps/search/?api=1&query=${job.locationLat},${job.locationLng}';

  // Title for share sheets that support it (iOS Mail subject line,
  // Android intent EXTRA_SUBJECT, Slack channel preview).
  final subject = '$pay · ${job.type.label} · ${job.locationAddress}';

  final body = StringBuffer()
    ..writeln(job.title)
    ..writeln()
    ..writeln('💵 $pay')
    ..writeln('⏱️  ${job.durationHours} ${job.durationHours == 1 ? "hour" : "hours"}')
    ..writeln('📍 ${job.locationAddress}')
    ..writeln('🏢 ${job.employer.name}')
    ..writeln('🗓️  ${dateFmt.format(job.startTime.toLocal())}')
    ..writeln()
    ..writeln('📍 Open in Maps:')
    ..writeln(mapsUrl)
    ..writeln()
    ..write('Posted on Forge.');

  await Share.share(body.toString(), subject: subject);
}
