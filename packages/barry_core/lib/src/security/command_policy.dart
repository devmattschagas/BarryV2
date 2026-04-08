class CommandPolicy {
  const CommandPolicy({required this.allowlistedCommands});
  final Set<String> allowlistedCommands;

  bool canExecute(String command) => allowlistedCommands.contains(command);
}

class CommandPolicies {
  static const zeptoClawCloud = CommandPolicy(
    allowlistedCommands: {
      'status.read',
      'sensors.scan',
      'nav.lock',
    },
  );
}
