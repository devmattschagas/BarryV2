class CommandPolicy {
  const CommandPolicy({required this.allowlistedCommands});
  final Set<String> allowlistedCommands;

  bool canExecute(String command) => allowlistedCommands.contains(command);
}
