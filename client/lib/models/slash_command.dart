class SlashCommand {
  final String name;
  final String description;

  const SlashCommand({required this.name, required this.description});

  factory SlashCommand.fromJson(Map<String, dynamic> json) => SlashCommand(
        name: json['name'] as String,
        description: json['description'] as String,
      );
}
