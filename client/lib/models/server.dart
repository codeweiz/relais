class Server {
  final String id;
  final String name;
  final String url;
  final String token;

  const Server({
    required this.id,
    required this.name,
    required this.url,
    required this.token,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'token': token,
  };

  factory Server.fromJson(Map<String, dynamic> json) => Server(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    token: json['token'] as String,
  );
}
