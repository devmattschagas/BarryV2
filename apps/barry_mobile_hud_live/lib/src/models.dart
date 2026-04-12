import 'dart:convert';

class ConversationMessage {
  ConversationMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String role;
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ConversationMessage.fromJson(Map<String, dynamic> map) => ConversationMessage(
        id: map['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        role: map['role'] as String? ?? 'assistant',
        text: map['text'] as String? ?? '',
        timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

class ConversationThread {
  ConversationThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final List<ConversationMessage> messages;

  ConversationThread copyWith({
    String? title,
    List<ConversationMessage>? messages,
  }) {
    return ConversationThread(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(growable: false),
      };

  factory ConversationThread.fromJson(Map<String, dynamic> map) => ConversationThread(
        id: map['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: map['title'] as String? ?? 'Nova conversa',
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        messages: (map['messages'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ConversationMessage.fromJson)
            .toList(),
      );
}

enum InferencePolicy { localOnly, hybridPreferLocal, hybridPreferRemote, remoteOnly }

class AssistantSettings {
  const AssistantSettings({
    required this.llmBaseUrl,
    required this.sttBaseUrl,
    required this.ttsBaseUrl,
    required this.memoryBaseUrl,
    required this.llmApiKey,
    required this.sttApiKey,
    required this.ttsApiKey,
    required this.model,
    required this.timeoutMs,
    required this.transport,
    required this.confirmTranscriptBeforeSend,
    required this.localModel,
    required this.localModelEnabled,
    required this.inferencePolicy,
    required this.zeptoLocalEnabled,
    required this.zeptoRemoteEnabled,
    required this.zeptoRemoteUrl,
    required this.zeptoRemoteApiKey,
  });

  final String llmBaseUrl;
  final String sttBaseUrl;
  final String ttsBaseUrl;
  final String memoryBaseUrl;
  final String llmApiKey;
  final String sttApiKey;
  final String ttsApiKey;
  final String model;
  final int timeoutMs;
  final String transport;
  final bool confirmTranscriptBeforeSend;
  final String localModel;
  final bool localModelEnabled;
  final InferencePolicy inferencePolicy;
  final bool zeptoLocalEnabled;
  final bool zeptoRemoteEnabled;
  final String zeptoRemoteUrl;
  final String zeptoRemoteApiKey;

  static const defaults = AssistantSettings(
    llmBaseUrl: '',
    sttBaseUrl: '',
    ttsBaseUrl: '',
    memoryBaseUrl: '',
    llmApiKey: '',
    sttApiKey: '',
    ttsApiKey: '',
    model: 'qwen2.5:7b-instruct',
    timeoutMs: 30000,
    transport: 'https',
    confirmTranscriptBeforeSend: true,
    localModel: 'gemma-2b-it-q4_0',
    localModelEnabled: true,
    inferencePolicy: InferencePolicy.hybridPreferLocal,
    zeptoLocalEnabled: true,
    zeptoRemoteEnabled: false,
    zeptoRemoteUrl: '',
    zeptoRemoteApiKey: '',
  );

  AssistantSettings copyWith({
    String? llmBaseUrl,
    String? sttBaseUrl,
    String? ttsBaseUrl,
    String? memoryBaseUrl,
    String? llmApiKey,
    String? sttApiKey,
    String? ttsApiKey,
    String? model,
    int? timeoutMs,
    String? transport,
    bool? confirmTranscriptBeforeSend,
    String? localModel,
    bool? localModelEnabled,
    InferencePolicy? inferencePolicy,
    bool? zeptoLocalEnabled,
    bool? zeptoRemoteEnabled,
    String? zeptoRemoteUrl,
    String? zeptoRemoteApiKey,
  }) {
    return AssistantSettings(
      llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
      sttBaseUrl: sttBaseUrl ?? this.sttBaseUrl,
      ttsBaseUrl: ttsBaseUrl ?? this.ttsBaseUrl,
      memoryBaseUrl: memoryBaseUrl ?? this.memoryBaseUrl,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      sttApiKey: sttApiKey ?? this.sttApiKey,
      ttsApiKey: ttsApiKey ?? this.ttsApiKey,
      model: model ?? this.model,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      transport: transport ?? this.transport,
      confirmTranscriptBeforeSend: confirmTranscriptBeforeSend ?? this.confirmTranscriptBeforeSend,
      localModel: localModel ?? this.localModel,
      localModelEnabled: localModelEnabled ?? this.localModelEnabled,
      inferencePolicy: inferencePolicy ?? this.inferencePolicy,
      zeptoLocalEnabled: zeptoLocalEnabled ?? this.zeptoLocalEnabled,
      zeptoRemoteEnabled: zeptoRemoteEnabled ?? this.zeptoRemoteEnabled,
      zeptoRemoteUrl: zeptoRemoteUrl ?? this.zeptoRemoteUrl,
      zeptoRemoteApiKey: zeptoRemoteApiKey ?? this.zeptoRemoteApiKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'llmBaseUrl': llmBaseUrl,
        'sttBaseUrl': sttBaseUrl,
        'ttsBaseUrl': ttsBaseUrl,
        'memoryBaseUrl': memoryBaseUrl,
        'llmApiKey': llmApiKey,
        'sttApiKey': sttApiKey,
        'ttsApiKey': ttsApiKey,
        'model': model,
        'timeoutMs': timeoutMs,
        'transport': transport,
        'confirmTranscriptBeforeSend': confirmTranscriptBeforeSend,
        'localModel': localModel,
        'localModelEnabled': localModelEnabled,
        'inferencePolicy': inferencePolicy.name,
        'zeptoLocalEnabled': zeptoLocalEnabled,
        'zeptoRemoteEnabled': zeptoRemoteEnabled,
        'zeptoRemoteUrl': zeptoRemoteUrl,
        'zeptoRemoteApiKey': zeptoRemoteApiKey,
      };

  factory AssistantSettings.fromJson(Map<String, dynamic> map) => AssistantSettings(
        llmBaseUrl: map['llmBaseUrl'] as String? ?? '',
        sttBaseUrl: map['sttBaseUrl'] as String? ?? '',
        ttsBaseUrl: map['ttsBaseUrl'] as String? ?? '',
        memoryBaseUrl: map['memoryBaseUrl'] as String? ?? '',
        llmApiKey: map['llmApiKey'] as String? ?? '',
        sttApiKey: map['sttApiKey'] as String? ?? '',
        ttsApiKey: map['ttsApiKey'] as String? ?? '',
        model: map['model'] as String? ?? 'gpt-4.1-mini',
        timeoutMs: (map['timeoutMs'] as num?)?.toInt() ?? 30000,
        transport: map['transport'] as String? ?? 'https',
        confirmTranscriptBeforeSend: map['confirmTranscriptBeforeSend'] as bool? ?? true,
        localModel: map['localModel'] as String? ?? 'gemma-2b-it-q4_0',
        localModelEnabled: map['localModelEnabled'] as bool? ?? true,
        inferencePolicy: InferencePolicy.values.firstWhere(
          (p) => p.name == map['inferencePolicy'],
          orElse: () => InferencePolicy.hybridPreferLocal,
        ),
        zeptoLocalEnabled: map['zeptoLocalEnabled'] as bool? ?? true,
        zeptoRemoteEnabled: map['zeptoRemoteEnabled'] as bool? ?? false,
        zeptoRemoteUrl: map['zeptoRemoteUrl'] as String? ?? '',
        zeptoRemoteApiKey: map['zeptoRemoteApiKey'] as String? ?? '',
      );
}

class UserProfile {
  const UserProfile({required this.name, required this.avatarPath});

  final String name;
  final String avatarPath;

  static const defaults = UserProfile(name: 'Operador', avatarPath: '');

  Map<String, dynamic> toJson() => {'name': name, 'avatarPath': avatarPath};

  factory UserProfile.fromJson(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return UserProfile(
      name: map['name'] as String? ?? 'Operador',
      avatarPath: map['avatarPath'] as String? ?? '',
    );
  }
}

enum AssistantState { idle, listening, processing, speaking, error }
