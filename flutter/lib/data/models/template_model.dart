enum Template { customerSupport, personalAssistant, navigationSystem, deviceControl }

extension TemplateExtension on Template {
  String get label {
    switch (this) {
      case Template.customerSupport:
        return 'Customer Support';
      case Template.personalAssistant:
        return 'Personal Assistant';
      case Template.navigationSystem:
        return 'Navigation System';
      case Template.deviceControl:
        return 'Device Control';
    }
  }

  String get description {
    switch (this) {
      case Template.customerSupport:
        return 'Handle customer inquiries and see how function calls can automate tasks.';
      case Template.personalAssistant:
        return 'Manage your schedule, send emails, and set reminders.';
      case Template.navigationSystem:
        return 'Find routes, nearby places, and get traffic information.';
      case Template.deviceControl:
        return 'Control your mobile device, inspect screens, navigate apps, and execute device actions.';
    }
  }

  List<String> get examplePrompts {
    switch (this) {
      case Template.customerSupport:
        return [
          "I'd like to return an item.",
          "What's the status of my order?",
          'Can I speak to a representative?',
        ];
      case Template.personalAssistant:
        return [
          'Create a calendar event for a meeting tomorrow at 10am.',
          'Send an email to jane@example.com.',
          'Set a reminder to buy milk.',
        ];
      case Template.navigationSystem:
        return [
          'Find a route to the nearest coffee shop.',
          'Are there any parks nearby?',
          "What's the traffic like on the way to the airport?",
        ];
      case Template.deviceControl:
        return [
          'Open the settings app on my phone.',
          'Swipe down to see notifications.',
          'Take a screenshot of my current screen.',
          'Find my phone and tap on it.',
          'Increase the screen brightness.',
          'List my installed apps.',
        ];
    }
  }
}