import '../errors.dart';
import '../guidance/pose.dart';
import '../result.dart';

/// Every user-facing string. Built-in: English, Spanish, French. Override any of them with
/// [FaceVerificationMessages.copyWith], or supply a whole set for another language.
class FaceVerificationMessages {
  const FaceVerificationMessages({
    required this.title,
    required this.introBody,
    required this.introTips,
    required this.privacyNote,
    required this.start,
    required this.cancel,
    required this.close,
    required this.done,
    required this.tryAgain,
    required this.starting,
    required this.stepOf,
    required this.guidance,
    required this.captured,
    required this.lookBack,
    required this.paused,
    required this.submitting,
    required this.successTitle,
    required this.successBody,
    required this.failureTitle,
    required this.failure,
    required this.errorTitle,
    required this.errors,
    required this.cameraLabel,
    required this.speechLocale,
  });

  final String title;
  final String introBody;
  final List<String> introTips;
  final String privacyNote;
  final String start;
  final String cancel;
  final String close;
  final String done;
  final String tryAgain;
  final String starting;
  final String Function(int step, int total) stepOf;
  final Map<Guidance, String> guidance;
  final String captured;
  final String lookBack;
  final String paused;
  final String submitting;
  final String successTitle;
  final String successBody;
  final String failureTitle;
  final Map<FaceFailureCode, String> failure;
  final String errorTitle;
  final Map<FaceVerificationErrorCode, String> errors;
  final String cameraLabel;

  /// BCP 47 locale for the device's text-to-speech voice.
  final String speechLocale;

  /// Built-in messages for [language] ("en", "es", "fr", or a regional tag like "es-MX");
  /// anything else falls back to English.
  static FaceVerificationMessages forLanguage(String language) => switch (language.toLowerCase().split(RegExp('[-_]')).first) {
    'es' => es,
    'fr' => fr,
    _ => en,
  };

  FaceVerificationMessages copyWith({
    String? title,
    String? introBody,
    List<String>? introTips,
    String? privacyNote,
    String? start,
    String? successTitle,
    String? successBody,
    String? failureTitle,
    Map<Guidance, String>? guidance,
    Map<FaceFailureCode, String>? failure,
    Map<FaceVerificationErrorCode, String>? errors,
  }) => FaceVerificationMessages(
    title: title ?? this.title,
    introBody: introBody ?? this.introBody,
    introTips: introTips ?? this.introTips,
    privacyNote: privacyNote ?? this.privacyNote,
    start: start ?? this.start,
    cancel: cancel,
    close: close,
    done: done,
    tryAgain: tryAgain,
    starting: starting,
    stepOf: stepOf,
    guidance: {...this.guidance, ...?guidance},
    captured: captured,
    lookBack: lookBack,
    paused: paused,
    submitting: submitting,
    successTitle: successTitle ?? this.successTitle,
    successBody: successBody ?? this.successBody,
    failureTitle: failureTitle ?? this.failureTitle,
    failure: {...this.failure, ...?failure},
    errorTitle: errorTitle,
    errors: {...this.errors, ...?errors},
    cameraLabel: cameraLabel,
    speechLocale: speechLocale,
  );

  static final en = FaceVerificationMessages(
    title: 'Verify your identity',
    introBody: "We'll take a few photos to confirm it's really you. It takes about 20 seconds.",
    introTips: const ['Find good lighting', 'Remove sunglasses or hats', 'Be the only person in view'],
    privacyNote: 'Your photos are used only for this check and are not stored.',
    start: 'Start',
    cancel: 'Cancel',
    close: 'Close',
    done: 'Done',
    tryAgain: 'Try again',
    starting: 'Starting the camera…',
    stepOf: (step, total) => 'Step $step of $total',
    guidance: const {
      Guidance.noFace: 'Position your face in the oval.',
      Guidance.multipleFaces: 'Make sure only you are in view.',
      Guidance.moveCloser: 'Move a little closer.',
      Guidance.moveBack: 'Move back a little.',
      Guidance.centerFace: 'Center your face in the oval.',
      Guidance.lookStraight: 'Look directly at the camera.',
      Guidance.turnLeft: 'Turn your head to the left.',
      Guidance.turnRight: 'Turn your head to the right.',
      Guidance.holdStill: 'Hold still.',
    },
    captured: 'Got it.',
    lookBack: 'Now look back at the camera.',
    paused: 'Paused. Return to the app to continue.',
    submitting: 'Verifying…',
    successTitle: 'Verification complete',
    successBody: "Thank you. You're all set.",
    failureTitle: "We couldn't verify you",
    failure: const {
      FaceFailureCode.noFace: "We couldn't see your face clearly. Try again in better light.",
      FaceFailureCode.multipleFaces: "More than one face was in view. Make sure you're alone.",
      FaceFailureCode.faceTooSmall: 'Your face was too far away. Move closer to the camera.',
      FaceFailureCode.lowConfidence: "The photo wasn't clear enough. Try again in better light.",
      FaceFailureCode.faceOutOfFrame: 'Part of your face was out of view. Keep it inside the oval.',
      FaceFailureCode.notFrontal: 'Look straight at the camera for the first photo.',
      FaceFailureCode.wrongPose: "The head turn wasn't clear. Turn a bit further when asked.",
      FaceFailureCode.invalidImage: "A photo couldn't be read. Please try again.",
      FaceFailureCode.livenessFailed: "We couldn't confirm a live person was present.",
      FaceFailureCode.notMatched: "Your face didn't match our records.",
      FaceFailureCode.referenceUnusable: "We couldn't use the photo on file. Please contact support.",
      FaceFailureCode.expired: 'This verification has expired.',
      FaceFailureCode.serviceUnavailable: 'The service is temporarily unavailable. Please try again later.',
      FaceFailureCode.failed: 'Something went wrong. Please try again.',
    },
    errorTitle: 'Something went wrong',
    errors: const {
      FaceVerificationErrorCode.configurationError: "This app isn't set up correctly. Please contact support.",
      FaceVerificationErrorCode.cameraDenied: 'Camera access is off. Allow it for this app in Settings, then try again.',
      FaceVerificationErrorCode.cameraNotFound: 'No camera was found on this device.',
      FaceVerificationErrorCode.cameraUnavailable: "The camera couldn't be started. Close other apps using it and try again.",
      FaceVerificationErrorCode.sessionUnavailable: "We couldn't start the verification. Please try again in a moment.",
      FaceVerificationErrorCode.invalidToken: 'This verification is no longer valid.',
      FaceVerificationErrorCode.sessionUsed: 'This verification has already been completed.',
      FaceVerificationErrorCode.sessionExpired: 'This verification has expired.',
      FaceVerificationErrorCode.referenceMissing: "This verification isn't ready yet. Please try again shortly.",
      FaceVerificationErrorCode.stepTimeout: "That took too long. Let's try again.",
      FaceVerificationErrorCode.networkError: "We couldn't connect. Check your connection and try again.",
      FaceVerificationErrorCode.serviceUnavailable: 'The service is temporarily unavailable. Please try again later.',
      FaceVerificationErrorCode.requestRejected: "The photos couldn't be processed. Please try again.",
      FaceVerificationErrorCode.cancelled: 'Verification cancelled.',
    },
    cameraLabel: 'Camera preview',
    speechLocale: 'en-US',
  );

  static final es = FaceVerificationMessages(
    title: 'Verifica tu identidad',
    introBody: 'Tomaremos algunas fotos para confirmar que eres tú. Tarda unos 20 segundos.',
    introTips: const ['Busca buena iluminación', 'Quítate gafas de sol o gorra', 'Asegúrate de estar solo'],
    privacyNote: 'Tus fotos se usan solo para esta verificación y no se guardan.',
    start: 'Comenzar',
    cancel: 'Cancelar',
    close: 'Cerrar',
    done: 'Listo',
    tryAgain: 'Intentar de nuevo',
    starting: 'Iniciando la cámara…',
    stepOf: (step, total) => 'Paso $step de $total',
    guidance: const {
      Guidance.noFace: 'Coloca tu cara dentro del óvalo.',
      Guidance.multipleFaces: 'Asegúrate de que solo tú estés a la vista.',
      Guidance.moveCloser: 'Acércate un poco.',
      Guidance.moveBack: 'Aléjate un poco.',
      Guidance.centerFace: 'Centra tu cara en el óvalo.',
      Guidance.lookStraight: 'Mira directamente a la cámara.',
      Guidance.turnLeft: 'Gira la cabeza hacia la izquierda.',
      Guidance.turnRight: 'Gira la cabeza hacia la derecha.',
      Guidance.holdStill: 'No te muevas.',
    },
    captured: 'Listo.',
    lookBack: 'Ahora vuelve a mirar a la cámara.',
    paused: 'En pausa. Vuelve a la app para continuar.',
    submitting: 'Verificando…',
    successTitle: 'Verificación completada',
    successBody: 'Gracias. Todo listo.',
    failureTitle: 'No pudimos verificarte',
    failure: {
      ...en.failure,
      FaceFailureCode.noFace: 'No pudimos ver bien tu cara. Inténtalo con mejor luz.',
      FaceFailureCode.multipleFaces: 'Había más de una cara a la vista. Asegúrate de estar solo.',
      FaceFailureCode.wrongPose: 'El giro de cabeza no fue claro. Gira un poco más cuando se te pida.',
      FaceFailureCode.livenessFailed: 'No pudimos confirmar que hubiera una persona presente.',
      FaceFailureCode.notMatched: 'Tu cara no coincide con nuestros registros.',
      FaceFailureCode.expired: 'Esta verificación ha caducado.',
      FaceFailureCode.failed: 'Algo salió mal. Inténtalo de nuevo.',
    },
    errorTitle: 'Algo salió mal',
    errors: {
      ...en.errors,
      FaceVerificationErrorCode.cameraDenied: 'El acceso a la cámara está desactivado. Permítelo en Ajustes e inténtalo de nuevo.',
      FaceVerificationErrorCode.cameraNotFound: 'No se encontró ninguna cámara en este dispositivo.',
      FaceVerificationErrorCode.sessionUnavailable: 'No pudimos iniciar la verificación. Inténtalo de nuevo en un momento.',
      FaceVerificationErrorCode.stepTimeout: 'Tardó demasiado. Intentémoslo de nuevo.',
      FaceVerificationErrorCode.networkError: 'No pudimos conectarnos. Revisa tu conexión e inténtalo de nuevo.',
      FaceVerificationErrorCode.cancelled: 'Verificación cancelada.',
    },
    cameraLabel: 'Vista previa de la cámara',
    speechLocale: 'es-ES',
  );

  static final fr = FaceVerificationMessages(
    title: 'Vérifiez votre identité',
    introBody: "Nous allons prendre quelques photos pour confirmer qu'il s'agit bien de vous. Cela prend environ 20 secondes.",
    introTips: const ['Placez-vous dans un endroit bien éclairé', 'Retirez lunettes de soleil et chapeau', 'Soyez seul dans le champ'],
    privacyNote: 'Vos photos servent uniquement à cette vérification et ne sont pas conservées.',
    start: 'Commencer',
    cancel: 'Annuler',
    close: 'Fermer',
    done: 'Terminé',
    tryAgain: 'Réessayer',
    starting: 'Démarrage de la caméra…',
    stepOf: (step, total) => 'Étape $step sur $total',
    guidance: const {
      Guidance.noFace: "Placez votre visage dans l'ovale.",
      Guidance.multipleFaces: "Assurez-vous d'être seul dans le champ.",
      Guidance.moveCloser: 'Rapprochez-vous un peu.',
      Guidance.moveBack: 'Reculez un peu.',
      Guidance.centerFace: "Centrez votre visage dans l'ovale.",
      Guidance.lookStraight: 'Regardez directement la caméra.',
      Guidance.turnLeft: 'Tournez la tête vers la gauche.',
      Guidance.turnRight: 'Tournez la tête vers la droite.',
      Guidance.holdStill: 'Ne bougez plus.',
    },
    captured: "C'est fait.",
    lookBack: 'Regardez de nouveau la caméra.',
    paused: "En pause. Revenez dans l'application pour continuer.",
    submitting: 'Vérification…',
    successTitle: 'Vérification terminée',
    successBody: 'Merci. Tout est en ordre.',
    failureTitle: "Nous n'avons pas pu vous vérifier",
    failure: {
      ...en.failure,
      FaceFailureCode.noFace: "Nous n'avons pas bien vu votre visage. Réessayez avec un meilleur éclairage.",
      FaceFailureCode.multipleFaces: "Plusieurs visages étaient visibles. Assurez-vous d'être seul.",
      FaceFailureCode.wrongPose: "Le mouvement de tête n'était pas net. Tournez un peu plus lorsque c'est demandé.",
      FaceFailureCode.livenessFailed: "Nous n'avons pas pu confirmer la présence d'une personne.",
      FaceFailureCode.notMatched: 'Votre visage ne correspond pas à nos données.',
      FaceFailureCode.expired: 'Cette vérification a expiré.',
      FaceFailureCode.failed: "Une erreur s'est produite. Veuillez réessayer.",
    },
    errorTitle: "Une erreur s'est produite",
    errors: {
      ...en.errors,
      FaceVerificationErrorCode.cameraDenied: "L'accès à la caméra est désactivé. Autorisez-le dans les Réglages, puis réessayez.",
      FaceVerificationErrorCode.cameraNotFound: 'Aucune caméra trouvée sur cet appareil.',
      FaceVerificationErrorCode.sessionUnavailable: 'Impossible de démarrer la vérification. Réessayez dans un instant.',
      FaceVerificationErrorCode.stepTimeout: 'Cela a pris trop de temps. Réessayons.',
      FaceVerificationErrorCode.networkError: 'Connexion impossible. Vérifiez votre connexion et réessayez.',
      FaceVerificationErrorCode.cancelled: 'Vérification annulée.',
    },
    cameraLabel: 'Aperçu de la caméra',
    speechLocale: 'fr-FR',
  );
}
