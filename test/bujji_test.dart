import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/buddy/bujji.dart';

// Bujji's rules, with the sentences people actually type.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  test('only messages that start with @bujji are for Bujji', () {
    expect(Bujji.forBujji('@bujji hi'), 'hi');
    expect(Bujji.forBujji('@Bujji, chat'), 'chat');
    expect(Bujji.forBujji('  @BUJJI what is up'), 'what is up');
    expect(Bujji.forBujji('hello @bujji'), isNull);
    expect(Bujji.forBujji('@bujjix hi'), isNull);
  });

  test('remembers a fact and answers a question about it', () async {
    final a = await Bujji.handle('naren phone number is 12257383929');
    expect(a.text, contains('12257383929'));
    final b = await Bujji.handle("whats naren phone number");
    expect(b.text, 'Naren phone number is 12257383929.');
    final c = await Bujji.handle("what's naren's phone number?");
    expect(c.text, 'Naren phone number is 12257383929.');
  });

  test('a birthday today plus a reminder at 3', () async {
    final a = await Bujji.handle(
      'gowthu birthday is today so remind me to ask her for a date at 3 o clock',
    );
    expect(a.text, contains('Gowthu birthday is'));
    expect(a.text, contains("I'll remind you"));
    expect(a.text, contains('ask her for a date'));
    final timed = Bujji.reminders.where((r) => r.text == 'ask her for a date');
    expect(timed.length, 1);
    expect(timed.first.next.hour, 15);
    expect(timed.first.next.isAfter(DateTime.now()), isTrue);
    expect(Bujji.reminders.where((r) => r.yearly).length, 1);
    final b = await Bujji.handle('when is gowthu birthday');
    expect(b.text, startsWith('Gowthu birthday is'));
  });

  test('reminders in a while, and asking when', () async {
    await Bujji.handle('remind me in 20 minutes to check the oven');
    final r = Bujji.reminders.firstWhere((r) => r.text == 'check the oven');
    final mins = r.next.difference(DateTime.now()).inMinutes;
    expect(mins, inInclusiveRange(18, 20));
    final ask = await Bujji.handle('remind me to call mom');
    expect(ask.text, contains('When should I remind you'));
    await Bujji.handle('remind me tomorrow at 9 am to call mom');
    final m = Bujji.reminders.firstWhere((r) => r.text == 'call mom');
    expect(m.next.hour, 9);
    expect(m.next.day, DateTime.now().add(const Duration(days: 1)).day);
  });

  test('forgets, opens its chat, keeps plain notes', () async {
    final f = await Bujji.handle('forget naren phone number');
    expect(f.text, startsWith('Forgotten'));
    final q = await Bujji.handle('whats naren phone number');
    expect(q.text, startsWith("I don't know"));
    expect((await Bujji.handle('chat')).openChat, isTrue);
    final n = await Bujji.handle('buy milk on the way home');
    expect(n.text, 'Saved as a note.');
    expect(Bujji.log.isNotEmpty, isTrue);
  });
}
