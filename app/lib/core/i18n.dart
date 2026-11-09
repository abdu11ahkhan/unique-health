/// Lightweight UI translations. English text is the key; anything not found falls back to English.
/// To add a language: add its code to [languages] and one map to [_t].
class I18n {
  static const languages = {'en': 'English', 'es': 'Español', 'fr': 'Français', 'de': 'Deutsch', 'ar': 'العربية', 'hi': 'हिन्दी', 'zh': '中文'};

  static String tr(String s, String lang) => lang == 'en' ? s : (_t[lang]?[s] ?? s);

  /// For tests: keys that have a translation in every language.
  static Iterable<String> get keys => _t['es']!.keys;
  static Map<String, String>? table(String lang) => _t[lang];

  static const Map<String, Map<String, String>> _t = {
    'es': {
      'Home': 'Inicio', 'Trend': 'Tendencia', 'Diet': 'Dieta', 'More': 'Más', 'Weight': 'Peso', 'Body Weight and Basic Indicators': 'Peso corporal e indicadores básicos', 'Body data': 'Datos corporales', 'This week': 'Esta semana',
      'Set a goal to track your progress': 'Fija una meta para seguir tu progreso', 'Measurement result': 'Resultado de la medición', 'Measure with scale': 'Medir con la báscula', 'Add weight manually': 'Añadir peso manualmente', 'Log food': 'Registrar comida',
      'Add device': 'Añadir dispositivo', 'Cancel': 'Cancelar', 'OK': 'Aceptar', 'Save': 'Guardar', 'Delete': 'Eliminar', 'Retry': 'Reintentar', 'Sign out': 'Cerrar sesión', 'Settings': 'Ajustes', 'General settings': 'Ajustes generales',
      'Member management': 'Gestión de miembros', 'Device management': 'Gestión de dispositivos', 'Data sharing': 'Compartir datos', 'Permission management': 'Gestión de permisos', 'Food Database': 'Base de datos de alimentos', 'Archives': 'Archivos', 'Setting': 'Configuración',
      'Feedback': 'Comentarios', 'Send feedback': 'Enviar comentarios', 'About': 'Acerca de', 'Messages': 'Mensajes', 'Mark all read': 'Marcar todo como leído', 'Weigh-in reminders': 'Recordatorios de pesaje', 'Health sync & export': 'Sincronización de salud y exportación',
      'Scan QR to log in': 'Escanear QR para iniciar sesión', 'Search for food calories': 'Buscar calorías de alimentos', 'Add food': 'Añadir comida', 'Food details': 'Detalles del alimento', 'Every 100 g': 'Por cada 100 g', 'Three major nutrients': 'Tres nutrientes principales',
      'Protein': 'Proteína', 'Fat': 'Grasa', 'Carbohydrate': 'Carbohidratos', 'Weekly summary': 'Resumen semanal', 'History': 'Historial', 'Recent records': 'Registros recientes', 'Standard': 'Estándar', 'Underweight': 'Bajo peso', 'Overweight': 'Sobrepeso', 'Obese': 'Obesidad',
      'Slightly low': 'Ligeramente bajo', 'Slightly high': 'Ligeramente alto', 'Excellent': 'Excelente', 'High': 'Alto', 'Very high': 'Muy alto', 'Insufficient': 'Insuficiente', 'Alert': 'Alerta', 'Weight unit': 'Unidad de peso', 'Dark mode': 'Modo oscuro', 'Server address': 'Dirección del servidor',
      'Change password': 'Cambiar contraseña', 'Delete account': 'Eliminar cuenta', 'Language': 'Idioma', 'Connected': 'Conectado', 'Offline': 'Sin conexión', 'Tips': 'Consejos', 'Health score': 'Puntuación de salud', 'Not good': 'Mala', 'Average': 'Media', 'Good': 'Buena', 'Very good': 'Muy buena',
      'Body fat': 'Grasa corporal', 'Muscle rate': 'Tasa muscular', 'Body water': 'Agua corporal', 'Visceral fat': 'Grasa visceral', 'Bone mass': 'Masa ósea', 'Sign in': 'Iniciar sesión', 'Create account': 'Crear cuenta', 'Email': 'Correo electrónico', 'Password': 'Contraseña',
    },
    'fr': {
      'Home': 'Accueil', 'Trend': 'Tendance', 'Diet': 'Alimentation', 'More': 'Plus', 'Weight': 'Poids', 'Body Weight and Basic Indicators': 'Poids corporel et indicateurs de base', 'Body data': 'Données corporelles', 'This week': 'Cette semaine',
      'Set a goal to track your progress': 'Fixez un objectif pour suivre vos progrès', 'Measurement result': 'Résultat de la mesure', 'Measure with scale': 'Mesurer avec la balance', 'Add weight manually': 'Ajouter le poids manuellement', 'Log food': 'Enregistrer un aliment',
      'Add device': 'Ajouter un appareil', 'Cancel': 'Annuler', 'OK': 'OK', 'Save': 'Enregistrer', 'Delete': 'Supprimer', 'Retry': 'Réessayer', 'Sign out': 'Se déconnecter', 'Settings': 'Paramètres', 'General settings': 'Paramètres généraux',
      'Member management': 'Gestion des membres', 'Device management': 'Gestion des appareils', 'Data sharing': 'Partage des données', 'Permission management': 'Gestion des autorisations', 'Food Database': 'Base de données alimentaire', 'Archives': 'Archives', 'Setting': 'Réglages',
      'Feedback': 'Commentaires', 'Send feedback': 'Envoyer un commentaire', 'About': 'À propos', 'Messages': 'Messages', 'Mark all read': 'Tout marquer comme lu', 'Weigh-in reminders': 'Rappels de pesée', 'Health sync & export': 'Synchronisation santé et export',
      'Scan QR to log in': 'Scanner le QR pour se connecter', 'Search for food calories': 'Rechercher les calories d’un aliment', 'Add food': 'Ajouter un aliment', 'Food details': 'Détails de l’aliment', 'Every 100 g': 'Pour 100 g', 'Three major nutrients': 'Trois nutriments principaux',
      'Protein': 'Protéines', 'Fat': 'Lipides', 'Carbohydrate': 'Glucides', 'Weekly summary': 'Résumé hebdomadaire', 'History': 'Historique', 'Recent records': 'Relevés récents', 'Standard': 'Normal', 'Underweight': 'Insuffisance pondérale', 'Overweight': 'Surpoids', 'Obese': 'Obésité',
      'Slightly low': 'Légèrement bas', 'Slightly high': 'Légèrement élevé', 'Excellent': 'Excellent', 'High': 'Élevé', 'Very high': 'Très élevé', 'Insufficient': 'Insuffisant', 'Alert': 'Alerte', 'Weight unit': 'Unité de poids', 'Dark mode': 'Mode sombre', 'Server address': 'Adresse du serveur',
      'Change password': 'Changer le mot de passe', 'Delete account': 'Supprimer le compte', 'Language': 'Langue', 'Connected': 'Connecté', 'Offline': 'Hors ligne', 'Tips': 'Conseils', 'Health score': 'Score de santé', 'Not good': 'Mauvais', 'Average': 'Moyen', 'Good': 'Bon', 'Very good': 'Très bon',
      'Body fat': 'Masse grasse', 'Muscle rate': 'Taux musculaire', 'Body water': 'Eau corporelle', 'Visceral fat': 'Graisse viscérale', 'Bone mass': 'Masse osseuse', 'Sign in': 'Se connecter', 'Create account': 'Créer un compte', 'Email': 'E-mail', 'Password': 'Mot de passe',
    },
    'de': {
      'Home': 'Start', 'Trend': 'Verlauf', 'Diet': 'Ernährung', 'More': 'Mehr', 'Weight': 'Gewicht', 'Body Weight and Basic Indicators': 'Körpergewicht und Basiswerte', 'Body data': 'Körperdaten', 'This week': 'Diese Woche',
      'Set a goal to track your progress': 'Setze ein Ziel, um deinen Fortschritt zu verfolgen', 'Measurement result': 'Messergebnis', 'Measure with scale': 'Mit Waage messen', 'Add weight manually': 'Gewicht manuell eintragen', 'Log food': 'Essen eintragen',
      'Add device': 'Gerät hinzufügen', 'Cancel': 'Abbrechen', 'OK': 'OK', 'Save': 'Speichern', 'Delete': 'Löschen', 'Retry': 'Erneut versuchen', 'Sign out': 'Abmelden', 'Settings': 'Einstellungen', 'General settings': 'Allgemeine Einstellungen',
      'Member management': 'Mitgliederverwaltung', 'Device management': 'Geräteverwaltung', 'Data sharing': 'Daten teilen', 'Permission management': 'Berechtigungen', 'Food Database': 'Lebensmitteldatenbank', 'Archives': 'Archiv', 'Setting': 'Einstellung',
      'Feedback': 'Feedback', 'Send feedback': 'Feedback senden', 'About': 'Über', 'Messages': 'Nachrichten', 'Mark all read': 'Alle als gelesen markieren', 'Weigh-in reminders': 'Wiege-Erinnerungen', 'Health sync & export': 'Gesundheitssync und Export',
      'Scan QR to log in': 'QR scannen zum Anmelden', 'Search for food calories': 'Kalorien von Lebensmitteln suchen', 'Add food': 'Essen hinzufügen', 'Food details': 'Lebensmitteldetails', 'Every 100 g': 'Pro 100 g', 'Three major nutrients': 'Drei Hauptnährstoffe',
      'Protein': 'Eiweiß', 'Fat': 'Fett', 'Carbohydrate': 'Kohlenhydrate', 'Weekly summary': 'Wochenübersicht', 'History': 'Verlauf', 'Recent records': 'Letzte Einträge', 'Standard': 'Normal', 'Underweight': 'Untergewicht', 'Overweight': 'Übergewicht', 'Obese': 'Adipositas',
      'Slightly low': 'Leicht niedrig', 'Slightly high': 'Leicht erhöht', 'Excellent': 'Ausgezeichnet', 'High': 'Hoch', 'Very high': 'Sehr hoch', 'Insufficient': 'Unzureichend', 'Alert': 'Achtung', 'Weight unit': 'Gewichtseinheit', 'Dark mode': 'Dunkelmodus', 'Server address': 'Serveradresse',
      'Change password': 'Passwort ändern', 'Delete account': 'Konto löschen', 'Language': 'Sprache', 'Connected': 'Verbunden', 'Offline': 'Offline', 'Tips': 'Tipps', 'Health score': 'Gesundheitswert', 'Not good': 'Schlecht', 'Average': 'Durchschnitt', 'Good': 'Gut', 'Very good': 'Sehr gut',
      'Body fat': 'Körperfett', 'Muscle rate': 'Muskelanteil', 'Body water': 'Körperwasser', 'Visceral fat': 'Viszerales Fett', 'Bone mass': 'Knochenmasse', 'Sign in': 'Anmelden', 'Create account': 'Konto erstellen', 'Email': 'E-Mail', 'Password': 'Passwort',
    },
    'ar': {
      'Home': 'الرئيسية', 'Trend': 'الاتجاه', 'Diet': 'النظام الغذائي', 'More': 'المزيد', 'Weight': 'الوزن', 'Body Weight and Basic Indicators': 'وزن الجسم والمؤشرات الأساسية', 'Body data': 'بيانات الجسم', 'This week': 'هذا الأسبوع',
      'Set a goal to track your progress': 'حدد هدفًا لتتبع تقدمك', 'Measurement result': 'نتيجة القياس', 'Measure with scale': 'القياس بالميزان', 'Add weight manually': 'إضافة الوزن يدويًا', 'Log food': 'تسجيل الطعام',
      'Add device': 'إضافة جهاز', 'Cancel': 'إلغاء', 'OK': 'موافق', 'Save': 'حفظ', 'Delete': 'حذف', 'Retry': 'إعادة المحاولة', 'Sign out': 'تسجيل الخروج', 'Settings': 'الإعدادات', 'General settings': 'الإعدادات العامة',
      'Member management': 'إدارة الأعضاء', 'Device management': 'إدارة الأجهزة', 'Data sharing': 'مشاركة البيانات', 'Permission management': 'إدارة الأذونات', 'Food Database': 'قاعدة بيانات الأغذية', 'Archives': 'الأرشيف', 'Setting': 'الإعداد',
      'Feedback': 'الملاحظات', 'Send feedback': 'إرسال ملاحظات', 'About': 'حول', 'Messages': 'الرسائل', 'Mark all read': 'تحديد الكل كمقروء', 'Weigh-in reminders': 'تذكيرات الوزن', 'Health sync & export': 'مزامنة الصحة والتصدير',
      'Scan QR to log in': 'امسح رمز QR لتسجيل الدخول', 'Search for food calories': 'ابحث عن سعرات الطعام', 'Add food': 'إضافة طعام', 'Food details': 'تفاصيل الطعام', 'Every 100 g': 'لكل 100 غرام', 'Three major nutrients': 'العناصر الغذائية الثلاثة الرئيسية',
      'Protein': 'البروتين', 'Fat': 'الدهون', 'Carbohydrate': 'الكربوهيدرات', 'Weekly summary': 'الملخص الأسبوعي', 'History': 'السجل', 'Recent records': 'أحدث السجلات', 'Standard': 'طبيعي', 'Underweight': 'نقص الوزن', 'Overweight': 'زيادة الوزن', 'Obese': 'سمنة',
      'Slightly low': 'منخفض قليلًا', 'Slightly high': 'مرتفع قليلًا', 'Excellent': 'ممتاز', 'High': 'مرتفع', 'Very high': 'مرتفع جدًا', 'Insufficient': 'غير كافٍ', 'Alert': 'تنبيه', 'Weight unit': 'وحدة الوزن', 'Dark mode': 'الوضع الداكن', 'Server address': 'عنوان الخادم',
      'Change password': 'تغيير كلمة المرور', 'Delete account': 'حذف الحساب', 'Language': 'اللغة', 'Connected': 'متصل', 'Offline': 'غير متصل', 'Tips': 'نصائح', 'Health score': 'درجة الصحة', 'Not good': 'سيئة', 'Average': 'متوسطة', 'Good': 'جيدة', 'Very good': 'جيدة جدًا',
      'Body fat': 'دهون الجسم', 'Muscle rate': 'نسبة العضلات', 'Body water': 'ماء الجسم', 'Visceral fat': 'الدهون الحشوية', 'Bone mass': 'كتلة العظام', 'Sign in': 'تسجيل الدخول', 'Create account': 'إنشاء حساب', 'Email': 'البريد الإلكتروني', 'Password': 'كلمة المرور',
    },
    'hi': {
      'Home': 'होम', 'Trend': 'रुझान', 'Diet': 'आहार', 'More': 'अधिक', 'Weight': 'वज़न', 'Body Weight and Basic Indicators': 'शरीर का वज़न और बुनियादी संकेतक', 'Body data': 'शरीर का डेटा', 'This week': 'इस सप्ताह',
      'Set a goal to track your progress': 'प्रगति देखने के लिए लक्ष्य तय करें', 'Measurement result': 'माप का परिणाम', 'Measure with scale': 'स्केल से मापें', 'Add weight manually': 'वज़न हाथ से जोड़ें', 'Log food': 'भोजन दर्ज करें',
      'Add device': 'डिवाइस जोड़ें', 'Cancel': 'रद्द करें', 'OK': 'ठीक है', 'Save': 'सहेजें', 'Delete': 'हटाएँ', 'Retry': 'फिर कोशिश करें', 'Sign out': 'साइन आउट', 'Settings': 'सेटिंग्स', 'General settings': 'सामान्य सेटिंग्स',
      'Member management': 'सदस्य प्रबंधन', 'Device management': 'डिवाइस प्रबंधन', 'Data sharing': 'डेटा साझा करना', 'Permission management': 'अनुमति प्रबंधन', 'Food Database': 'खाद्य डेटाबेस', 'Archives': 'अभिलेख', 'Setting': 'सेटिंग',
      'Feedback': 'प्रतिक्रिया', 'Send feedback': 'प्रतिक्रिया भेजें', 'About': 'जानकारी', 'Messages': 'संदेश', 'Mark all read': 'सभी को पढ़ा हुआ चिह्नित करें', 'Weigh-in reminders': 'वज़न रिमाइंडर', 'Health sync & export': 'स्वास्थ्य सिंक और निर्यात',
      'Scan QR to log in': 'लॉग इन के लिए QR स्कैन करें', 'Search for food calories': 'भोजन की कैलोरी खोजें', 'Add food': 'भोजन जोड़ें', 'Food details': 'भोजन का विवरण', 'Every 100 g': 'प्रति 100 ग्राम', 'Three major nutrients': 'तीन प्रमुख पोषक तत्व',
      'Protein': 'प्रोटीन', 'Fat': 'वसा', 'Carbohydrate': 'कार्बोहाइड्रेट', 'Weekly summary': 'साप्ताहिक सारांश', 'History': 'इतिहास', 'Recent records': 'हाल के रिकॉर्ड', 'Standard': 'सामान्य', 'Underweight': 'कम वज़न', 'Overweight': 'अधिक वज़न', 'Obese': 'मोटापा',
      'Slightly low': 'थोड़ा कम', 'Slightly high': 'थोड़ा अधिक', 'Excellent': 'उत्कृष्ट', 'High': 'उच्च', 'Very high': 'बहुत उच्च', 'Insufficient': 'अपर्याप्त', 'Alert': 'चेतावनी', 'Weight unit': 'वज़न की इकाई', 'Dark mode': 'डार्क मोड', 'Server address': 'सर्वर पता',
      'Change password': 'पासवर्ड बदलें', 'Delete account': 'खाता हटाएँ', 'Language': 'भाषा', 'Connected': 'जुड़ा हुआ', 'Offline': 'ऑफ़लाइन', 'Tips': 'सुझाव', 'Health score': 'स्वास्थ्य स्कोर', 'Not good': 'अच्छा नहीं', 'Average': 'औसत', 'Good': 'अच्छा', 'Very good': 'बहुत अच्छा',
      'Body fat': 'शरीर की चर्बी', 'Muscle rate': 'मांसपेशी दर', 'Body water': 'शरीर में पानी', 'Visceral fat': 'आंतरिक चर्बी', 'Bone mass': 'हड्डी का द्रव्यमान', 'Sign in': 'साइन इन', 'Create account': 'खाता बनाएँ', 'Email': 'ईमेल', 'Password': 'पासवर्ड',
    },
    'zh': {
      'Home': '首页', 'Trend': '趋势', 'Diet': '饮食', 'More': '更多', 'Weight': '体重', 'Body Weight and Basic Indicators': '体重与基础指标', 'Body data': '身体数据', 'This week': '本周',
      'Set a goal to track your progress': '设定目标以跟踪进度', 'Measurement result': '测量结果', 'Measure with scale': '用体脂秤测量', 'Add weight manually': '手动添加体重', 'Log food': '记录食物',
      'Add device': '添加设备', 'Cancel': '取消', 'OK': '确定', 'Save': '保存', 'Delete': '删除', 'Retry': '重试', 'Sign out': '退出登录', 'Settings': '设置', 'General settings': '通用设置',
      'Member management': '成员管理', 'Device management': '设备管理', 'Data sharing': '数据共享', 'Permission management': '权限管理', 'Food Database': '食物数据库', 'Archives': '档案', 'Setting': '设置项',
      'Feedback': '反馈', 'Send feedback': '发送反馈', 'About': '关于', 'Messages': '消息', 'Mark all read': '全部标为已读', 'Weigh-in reminders': '称重提醒', 'Health sync & export': '健康同步与导出',
      'Scan QR to log in': '扫码登录', 'Search for food calories': '搜索食物热量', 'Add food': '添加食物', 'Food details': '食物详情', 'Every 100 g': '每100克', 'Three major nutrients': '三大营养素',
      'Protein': '蛋白质', 'Fat': '脂肪', 'Carbohydrate': '碳水化合物', 'Weekly summary': '每周总结', 'History': '历史', 'Recent records': '最近记录', 'Standard': '标准', 'Underweight': '偏瘦', 'Overweight': '超重', 'Obese': '肥胖',
      'Slightly low': '偏低', 'Slightly high': '偏高', 'Excellent': '优秀', 'High': '高', 'Very high': '很高', 'Insufficient': '不足', 'Alert': '警示', 'Weight unit': '体重单位', 'Dark mode': '深色模式', 'Server address': '服务器地址',
      'Change password': '修改密码', 'Delete account': '删除账号', 'Language': '语言', 'Connected': '已连接', 'Offline': '离线', 'Tips': '建议', 'Health score': '健康评分', 'Not good': '较差', 'Average': '一般', 'Good': '良好', 'Very good': '很好',
      'Body fat': '体脂率', 'Muscle rate': '肌肉率', 'Body water': '水分', 'Visceral fat': '内脏脂肪', 'Bone mass': '骨量', 'Sign in': '登录', 'Create account': '创建账号', 'Email': '邮箱', 'Password': '密码',
    },
  };
}
