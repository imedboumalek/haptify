/// JSON key and value constants for the AHAP (Apple Haptic and Audio
/// Pattern) format.
library;

/// Top-level format version key.
const String kVersion = 'Version';

/// Top-level metadata object key.
const String kMetadata = 'Metadata';

/// Metadata project name key.
const String kMetadataProject = 'Project';

/// Metadata description key.
const String kMetadataDescription = 'Description';

/// Metadata creation date key.
const String kMetadataCreated = 'Created';

/// Top-level pattern array key.
const String kPattern = 'Pattern';

/// Pattern entry key holding a haptic event.
const String kEvent = 'Event';

/// Pattern entry key holding a dynamic parameter change.
const String kParameter = 'Parameter';

/// Pattern entry key holding a dynamic parameter curve.
const String kParameterCurve = 'ParameterCurve';

/// Event and entry start time key (seconds).
const String kTime = 'Time';

/// Event type key.
const String kEventType = 'EventType';

/// Event duration key (seconds), required for continuous events.
const String kEventDuration = 'EventDuration';

/// Event parameter array key.
const String kEventParameters = 'EventParameters';

/// Parameter identifier key.
const String kParameterId = 'ParameterID';

/// Parameter value key.
const String kParameterValue = 'ParameterValue';

/// Parameter curve control point array key.
const String kParameterCurveControlPoints = 'ParameterCurveControlPoints';

/// Transient event type value.
const String kHapticTransient = 'HapticTransient';

/// Continuous event type value.
const String kHapticContinuous = 'HapticContinuous';

/// Event intensity parameter ID.
const String kHapticIntensity = 'HapticIntensity';

/// Event sharpness parameter ID.
const String kHapticSharpness = 'HapticSharpness';

/// Envelope attack time parameter ID.
const String kAttackTime = 'AttackTime';

/// Envelope decay time parameter ID.
const String kDecayTime = 'DecayTime';

/// Envelope release time parameter ID.
const String kReleaseTime = 'ReleaseTime';

/// Envelope sustained flag parameter ID.
const String kSustained = 'Sustained';

/// Dynamic intensity control parameter ID.
const String kHapticIntensityControl = 'HapticIntensityControl';

/// Dynamic sharpness control parameter ID.
const String kHapticSharpnessControl = 'HapticSharpnessControl';

/// Dynamic attack time control parameter ID.
const String kHapticAttackTimeControl = 'HapticAttackTimeControl';

/// Dynamic decay time control parameter ID.
const String kHapticDecayTimeControl = 'HapticDecayTimeControl';

/// Dynamic release time control parameter ID.
const String kHapticReleaseTimeControl = 'HapticReleaseTimeControl';

/// The maximum number of control points Core Haptics accepts per curve.
const int kMaxCurveControlPoints = 16;
