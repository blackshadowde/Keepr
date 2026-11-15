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
    // "her" is the person just talked about
    expect(a.text, contains('ask Gowthu for a date'));
    final timed = Bujji.reminders.where((r) => r.text == 'ask Gowthu for a date');
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
    // not sure what this is: it asks, and learns from the answer
    final n = await Bujji.handle('buy milk on the way home');
    expect(n.choices.map((c) => c.id), ['remember', 'remind', 'ask']);
    final c = await Bujji.choose(n.choices.first);
    expect(c.text, 'Saved as a note.');
    final again = await Bujji.handle('buy eggs too');
    expect(again.text, 'Saved as a note.');
    expect(Bujji.log.isNotEmpty, isTrue);
  });

  BujjiReminder only(String text) =>
      Bujji.reminders.singleWhere((r) => r.text == text);

  test('the time can come first, and "ping me" is a reminder', () async {
    await Bujji.handle('at 3 remind me to call dad');
    expect(only('call dad').next.hour, 15);
    await Bujji.handle('ping me in half an hour to stretch');
    final m = only('stretch').next.difference(DateTime.now()).inMinutes;
    expect(m, inInclusiveRange(28, 30));
  });

  test("don't let me forget, and repeating reminders", () async {
    await Bujji.handle("Please don't let me forget to pay rent tomorrow");
    final rent = only('pay rent').next;
    expect(rent.hour, 9);
    expect(rent.day, DateTime.now().add(const Duration(days: 1)).day);
    final w = await Bujji.handle('remind me every monday at 10 to send report');
    expect(w.text, contains('every Monday'));
    final r = only('send report');
    expect(r.repeat, 'weekly');
    expect(r.next.weekday, DateTime.monday);
    expect(r.next.hour, 10);
    await Bujji.handle('remind me to take vitamins every day at 8 am');
    expect(only('take vitamins').repeat, 'daily');
  });

  test('other words for the same thing, and small slips', () async {
    await Bujji.handle('naren phone number is 98480');
    expect((await Bujji.handle('whats narens mobile')).text, contains('98480'));
    expect((await Bujji.handle('naren phne number?')).text, contains('98480'));
    expect((await Bujji.handle('when was gowthu born')).text, startsWith('Gowthu birthday'));
  });

  test('asks for the time, then takes it on its own', () async {
    final a = await Bujji.handle('remind me to water plants');
    expect(a.text, contains('When should I remind you'));
    await Bujji.handle('at 6 pm');
    expect(only('water plants').next.hour, 18);
  });

  test('"her" in a reminder is the person just mentioned', () async {
    await Bujji.handle('gowthu birthday is today, remind me to wish her tonight');
    expect(only('wish Gowthu').next.hour, 21);
  });
}
