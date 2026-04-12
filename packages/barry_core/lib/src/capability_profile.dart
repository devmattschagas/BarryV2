class CapabilityProfile {
  const CapabilityProfile({
    required this.hasLocalVad,
    required this.hasLocalStt,
    required this.hasRemoteStt,
    required this.hasLocalTts,
    required this.hasRemoteTts,
    required this.hasLocalLlm,
    required this.hasCloudQwen,
    required this.hasZeptoClawCloud,
    required this.hasVault,
    required this.hasClaudeMem,
    required this.hasPaul,
    required this.hasRealtimeRemoteTransport,
    required this.hasEmbeddingsLocal,
    required this.hasEmbeddingsRemote,
    this.remoteTransport = RemoteTransport.none,
  });

  final bool hasLocalVad;
  final bool hasLocalStt;
  final bool hasRemoteStt;
  final bool hasLocalTts;
  final bool hasRemoteTts;
  final bool hasLocalLlm;
  final bool hasCloudQwen;
  final bool hasZeptoClawCloud;
  final bool hasVault;
  final bool hasClaudeMem;
  final bool hasPaul;
  final bool hasRealtimeRemoteTransport;
  final bool hasEmbeddingsLocal;
  final bool hasEmbeddingsRemote;
  final RemoteTransport remoteTransport;



  CapabilityProfile copyWith({
    bool? hasLocalVad,
    bool? hasLocalStt,
    bool? hasRemoteStt,
    bool? hasLocalTts,
    bool? hasRemoteTts,
    bool? hasLocalLlm,
    bool? hasCloudQwen,
    bool? hasZeptoClawCloud,
    bool? hasVault,
    bool? hasClaudeMem,
    bool? hasPaul,
    bool? hasRealtimeRemoteTransport,
    bool? hasEmbeddingsLocal,
    bool? hasEmbeddingsRemote,
    RemoteTransport? remoteTransport,
  }) {
    return CapabilityProfile(
      hasLocalVad: hasLocalVad ?? this.hasLocalVad,
      hasLocalStt: hasLocalStt ?? this.hasLocalStt,
      hasRemoteStt: hasRemoteStt ?? this.hasRemoteStt,
      hasLocalTts: hasLocalTts ?? this.hasLocalTts,
      hasRemoteTts: hasRemoteTts ?? this.hasRemoteTts,
      hasLocalLlm: hasLocalLlm ?? this.hasLocalLlm,
      hasCloudQwen: hasCloudQwen ?? this.hasCloudQwen,
      hasZeptoClawCloud: hasZeptoClawCloud ?? this.hasZeptoClawCloud,
      hasVault: hasVault ?? this.hasVault,
      hasClaudeMem: hasClaudeMem ?? this.hasClaudeMem,
      hasPaul: hasPaul ?? this.hasPaul,
      hasRealtimeRemoteTransport: hasRealtimeRemoteTransport ?? this.hasRealtimeRemoteTransport,
      hasEmbeddingsLocal: hasEmbeddingsLocal ?? this.hasEmbeddingsLocal,
      hasEmbeddingsRemote: hasEmbeddingsRemote ?? this.hasEmbeddingsRemote,
      remoteTransport: remoteTransport ?? this.remoteTransport,
    );
  }
  static const empty = CapabilityProfile(
    hasLocalVad: false,
    hasLocalStt: false,
    hasRemoteStt: false,
    hasLocalTts: false,
    hasRemoteTts: false,
    hasLocalLlm: false,
    hasCloudQwen: false,
    hasZeptoClawCloud: false,
    hasVault: false,
    hasClaudeMem: false,
    hasPaul: false,
    hasRealtimeRemoteTransport: false,
    hasEmbeddingsLocal: false,
    hasEmbeddingsRemote: false,
  );
}

enum RemoteTransport { none, webrtc, websocket, http }

class CapabilityDetector {
  const CapabilityDetector();

  CapabilityProfile detect({
    required bool networkHealthy,
    required bool nativeVadLoaded,
    required bool localLlmBridgeAvailable,
    required bool localSttAvailable,
    required bool localTtsAvailable,
    required bool remoteQwenConfigured,
    required bool remoteSttConfigured,
    required bool remoteTtsConfigured,
    required bool zeptoClawConfigured,
    required bool vaultConfigured,
    required bool claudeMemConfigured,
    required bool paulConfigured,
    required bool embeddingsRemoteConfigured,
    required RemoteTransport remoteTransport,
  }) {
    return CapabilityProfile(
      hasLocalVad: nativeVadLoaded,
      hasLocalStt: localSttAvailable,
      hasRemoteStt: networkHealthy && remoteSttConfigured,
      hasLocalTts: localTtsAvailable,
      hasRemoteTts: networkHealthy && remoteTtsConfigured,
      hasLocalLlm: localLlmBridgeAvailable,
      hasCloudQwen: networkHealthy && remoteQwenConfigured,
      hasZeptoClawCloud: networkHealthy && zeptoClawConfigured,
      hasVault: networkHealthy && vaultConfigured,
      hasClaudeMem: networkHealthy && claudeMemConfigured,
      hasPaul: networkHealthy && paulConfigured,
      hasRealtimeRemoteTransport: networkHealthy && remoteTransport == RemoteTransport.webrtc,
      hasEmbeddingsLocal: true,
      hasEmbeddingsRemote: networkHealthy && embeddingsRemoteConfigured,
      remoteTransport: remoteTransport,
    );
  }
}
