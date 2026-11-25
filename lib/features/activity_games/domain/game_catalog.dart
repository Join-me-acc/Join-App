import 'package:flutter/material.dart';
import 'package:join_app/core/models/interest_model.dart';

/// Los juegos que ofrece el centro de juegos.
enum GameKind {
  impostorOnline,
  impostorLocal,
  dice,
  initial,
  teams,
  scoreboard,
  bracket,
  trivia,
  bingo,
  wouldYouRather,
  mostLikely,
  debate,
}

/// Lo que se ve de un juego en el catálogo.
class GameInfo {
  final GameKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int minPlayers;
  final int? maxPlayers;
  final int minutes;

  const GameInfo({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.minPlayers,
    this.maxPlayers,
    required this.minutes,
  });

  String get meta {
    final players = maxPlayers == null
        ? '$minPlayers+ personas'
        : '$minPlayers–$maxPlayers personas';
    return '$players · $minutes min';
  }
}

/// Pregunta de trivia con una sola respuesta correcta.
class TriviaQuestion {
  final String question;
  final List<String> options;
  final int answer;
  final String? fact;

  const TriviaQuestion(this.question, this.options, this.answer, {this.fact})
      : assert(answer >= 0);
}

/// Todo el contenido de juegos que corresponde a un plan.
class GamePack {
  /// Categoría principal reconocida ("Deportes", "Comida"...), o null.
  final String? mainCategory;

  /// Subcategoría más específica reconocida, si la hay ("Fútbol").
  final String? subcategory;

  final List<String> impostorWords;
  final List<String> initialChallenges;
  final List<TriviaQuestion> trivia;
  final List<String> bingo;
  final List<(String, String)> wouldYouRather;
  final List<String> mostLikely;
  final List<String> debateTopics;

  /// Juegos sugeridos para este plan, del más al menos recomendado.
  final List<GameKind> featured;

  const GamePack({
    required this.mainCategory,
    required this.subcategory,
    required this.impostorWords,
    required this.initialChallenges,
    required this.trivia,
    required this.bingo,
    required this.wouldYouRather,
    required this.mostLikely,
    required this.debateTopics,
    required this.featured,
  });

  /// Nombre para mostrar: la subcategoría si es más precisa.
  String get label => subcategory ?? mainCategory ?? 'tu plan';

  /// Color del plan para el centro de juegos.
  Color get accent =>
      CategoryConstants.colors[mainCategory] ?? const Color(0xFFFD7C36);

  IconData get icon =>
      CategoryConstants.icons[subcategory ?? mainCategory] ??
      Icons.celebration_rounded;
}

/// Catálogo tipado de juegos y contenido por categoría.
///
/// Sigue la misma regla que [ActivityRecommendations]: el contenido de una
/// subcategoría manda sobre el de su principal (para una pichanga sirven más
/// palabras de fútbol que de deporte en general), y se completa con el de la
/// principal para que nunca falte de dónde elegir.
class GameCatalog {
  GameCatalog._();

  // ══════════════════════════════════════════════════════════════
  //  Metadatos de cada juego
  // ══════════════════════════════════════════════════════════════

  static const Map<GameKind, GameInfo> info = {
    GameKind.impostorOnline: GameInfo(
      kind: GameKind.impostorOnline,
      title: 'El Impostor en línea',
      subtitle: 'Cada uno ve su rol en su propio celular',
      icon: Icons.wifi_tethering_rounded,
      color: Color(0xFF8B5CF6),
      minPlayers: 3,
      maxPlayers: 12,
      minutes: 6,
    ),
    GameKind.impostorLocal: GameInfo(
      kind: GameKind.impostorLocal,
      title: 'El Impostor (un celular)',
      subtitle: 'Pasen el teléfono y descubran quién miente',
      icon: Icons.visibility_off_rounded,
      color: Color(0xFFC084FC),
      minPlayers: 3,
      maxPlayers: 12,
      minutes: 5,
    ),
    GameKind.dice: GameInfo(
      kind: GameKind.dice,
      title: 'Dados virtuales',
      subtitle: 'Decidan turnos, equipos o pequeños retos',
      icon: Icons.casino_rounded,
      color: Color(0xFF38BDF8),
      minPlayers: 2,
      minutes: 1,
    ),
    GameKind.initial: GameInfo(
      kind: GameKind.initial,
      title: 'Reto por inicial',
      subtitle: 'Una letra al azar y un reto para quien la tenga',
      icon: Icons.shuffle_rounded,
      color: Color(0xFFFB7185),
      minPlayers: 3,
      minutes: 3,
    ),
    GameKind.teams: GameInfo(
      kind: GameKind.teams,
      title: 'Armar equipos',
      subtitle: 'Equipos parejos y al azar con la gente del plan',
      icon: Icons.groups_2_rounded,
      color: Color(0xFF22C55E),
      minPlayers: 2,
      minutes: 1,
    ),
    GameKind.scoreboard: GameInfo(
      kind: GameKind.scoreboard,
      title: 'Marcador rápido',
      subtitle: 'Lleven la cuenta del partido sin papel',
      icon: Icons.scoreboard_rounded,
      color: Color(0xFFF97316),
      minPlayers: 2,
      minutes: 1,
    ),
    GameKind.bracket: GameInfo(
      kind: GameKind.bracket,
      title: 'Bracket rápido',
      subtitle: 'Torneo de eliminación directa en segundos',
      icon: Icons.account_tree_rounded,
      color: Color(0xFF14B8A6),
      minPlayers: 3,
      maxPlayers: 16,
      minutes: 2,
    ),
    GameKind.trivia: GameInfo(
      kind: GameKind.trivia,
      title: 'Trivia del plan',
      subtitle: 'Preguntas pensadas para esta actividad',
      icon: Icons.quiz_rounded,
      color: Color(0xFFEAB308),
      minPlayers: 2,
      minutes: 5,
    ),
    GameKind.bingo: GameInfo(
      kind: GameKind.bingo,
      title: 'Bingo de exploración',
      subtitle: 'Encuentren todo lo del cartón durante el plan',
      icon: Icons.grid_on_rounded,
      color: Color(0xFF10B981),
      minPlayers: 1,
      minutes: 30,
    ),
    GameKind.wouldYouRather: GameInfo(
      kind: GameKind.wouldYouRather,
      title: '¿Qué prefieres?',
      subtitle: 'Dos opciones, una sola elección. Defiéndela',
      icon: Icons.call_split_rounded,
      color: Color(0xFF6366F1),
      minPlayers: 2,
      minutes: 5,
    ),
    GameKind.mostLikely: GameInfo(
      kind: GameKind.mostLikely,
      title: '¿Quién es más probable?',
      subtitle: 'A la cuenta de tres, todos señalan a alguien',
      icon: Icons.back_hand_rounded,
      color: Color(0xFFEC4899),
      minPlayers: 3,
      minutes: 5,
    ),
    GameKind.debate: GameInfo(
      kind: GameKind.debate,
      title: 'Debate exprés',
      subtitle: 'Un minuto por bando sobre un tema al azar',
      icon: Icons.record_voice_over_rounded,
      color: Color(0xFF0EA5E9),
      minPlayers: 2,
      minutes: 6,
    ),
  };

  /// Clásicos que sirven para cualquier plan.
  static const List<GameKind> classics = [
    GameKind.impostorLocal,
    GameKind.dice,
    GameKind.initial,
  ];

  // ══════════════════════════════════════════════════════════════
  //  Juegos sugeridos por categoría principal
  // ══════════════════════════════════════════════════════════════

  static const Map<String, List<GameKind>> _featured = {
    'Deportes': [GameKind.teams, GameKind.scoreboard, GameKind.trivia],
    'Comida': [GameKind.trivia, GameKind.wouldYouRather, GameKind.mostLikely],
    'Naturaleza': [GameKind.bingo, GameKind.trivia, GameKind.wouldYouRather],
    'Chill': [GameKind.wouldYouRather, GameKind.trivia, GameKind.mostLikely],
    'Juntas': [GameKind.mostLikely, GameKind.wouldYouRather, GameKind.teams],
    'Académico': [GameKind.trivia, GameKind.debate, GameKind.teams],
    'Juegos online': [GameKind.bracket, GameKind.teams, GameKind.trivia],
  };

  static const List<GameKind> _genericFeatured = [
    GameKind.wouldYouRather,
    GameKind.mostLikely,
    GameKind.trivia,
  ];

  // ══════════════════════════════════════════════════════════════
  //  Palabras de El Impostor
  // ══════════════════════════════════════════════════════════════

  static const List<String> _genericWords = [
    'Karaoke', 'La playa', 'Cumbia', 'Machu Picchu', 'Pisco sour', 'Cine',
    'Cumpleaños', 'Combi', 'Selfie', 'Mercado', 'Feriado', 'Parque',
  ];

  static const Map<String, List<String>> _words = {
    // ── Principales ─────────────────────────────────────────────
    'Deportes': [
      'Cancha', 'Árbitro', 'Camiseta', 'Pelota', 'Capitán', 'Tribuna',
      'Medalla', 'Calentamiento', 'Silbato', 'Penal', 'Vestuario', 'Hidratación',
    ],
    'Comida': [
      'Ceviche', 'Anticuchos', 'Chifa', 'Lomo saltado', 'Ají de gallina',
      'Picarones', 'Causa', 'Chicha morada', 'Pollo a la brasa', 'Rocoto',
      'Menú del día', 'Sanguchería',
    ],
    'Naturaleza': [
      'Mirador', 'Mochila', 'Fogata', 'Sendero', 'Cascada', 'Campamento',
      'Brújula', 'Neblina', 'Laguna', 'Linterna', 'Cóndor', 'Atardecer',
    ],
    'Chill': [
      'Manta', 'Café', 'Pochoclo', 'Playlist', 'Sofá', 'Maratón de series',
      'Audífonos', 'Librería', 'Juego de mesa', 'Siesta', 'Té', 'Vinilo',
    ],
    'Juntas': [
      'DJ', 'Torta', 'Pista de baile', 'Brindis', 'Globos', 'Karaoke',
      'Hora loca', 'Selfie grupal', 'Confeti', 'After', 'Invitación', 'Regalo',
    ],
    'Académico': [
      'Pizarra', 'Examen', 'Biblioteca', 'Resaltador', 'Exposición', 'Tesis',
      'Laboratorio', 'Apuntes', 'Profesor', 'Diapositivas', 'Calculadora',
      'Trabajo grupal',
    ],
    'Juegos online': [
      'Control', 'Nivel', 'Equipo', 'Torneo', 'Avatar', 'Misión', 'Lag',
      'Respawn', 'Jefe final', 'Skin', 'Ranking', 'Micrófono',
    ],

    // ── Subcategorías ───────────────────────────────────────────
    'Fútbol': [
      'Chimpunes', 'Pichanga', 'Tiro libre', 'Arquero', 'Córner', 'Offside',
      'Tarjeta roja', 'Hinchada', 'Gol olímpico', 'Canilleras',
    ],
    'Vóley': ['Saque', 'Remate', 'Red', 'Bloqueo', 'Rodilleras', 'Líbero'],
    'Básquet': ['Triple', 'Tablero', 'Rebote', 'Clavada', 'Aro', 'Tiempo muerto'],
    'Running': ['Meta', 'Cronómetro', 'Kilómetro', 'Zapatillas', 'Ritmo', 'Medalla'],
    'Trekking': ['Bastones', 'Cumbre', 'Altura', 'Mapa', 'Mochila', 'Mate de coca'],
    'Ciclismo': ['Casco', 'Pedal', 'Cadena', 'Bajada', 'Ciclovía', 'Parche'],
    'Natación': ['Piscina', 'Gorro', 'Lentes', 'Carril', 'Clavado', 'Mariposa'],
    'Gimnasio': ['Mancuernas', 'Pesas', 'Proteína', 'Sentadilla', 'Rutina', 'Espejo'],
    'Yoga': ['Mat', 'Respiración', 'Postura del árbol', 'Saludo al sol', 'Incienso'],
    'Parrilladas': ['Carbón', 'Chorizo', 'Chimichurri', 'Parrillero', 'Brasa', 'Pinzas'],
    'Cafetería': ['Capuchino', 'Barista', 'Croissant', 'Latte art', 'Espresso'],
    'Postres': ['Suspiro limeño', 'Mazamorra', 'Tres leches', 'Alfajor', 'Helado'],
    'Cocina': ['Delantal', 'Sartén', 'Receta', 'Cuchillo', 'Olla', 'Aderezo'],
    'Playa': ['Sombrilla', 'Bloqueador', 'Ola', 'Tabla', 'Arena', 'Raspadilla'],
    'Camping': ['Carpa', 'Sleeping', 'Fogata', 'Malvaviscos', 'Estrellas', 'Linterna'],
    'Viajes': ['Pasaporte', 'Maleta', 'Terminal', 'Hostal', 'Souvenir', 'Mapa'],
    'Mascotas': ['Correa', 'Croquetas', 'Pelotita', 'Veterinario', 'Collar'],
    'Cine': ['Butaca', 'Tráiler', 'Canchita', 'Spoiler', 'Estreno', 'Créditos'],
    'Series': ['Temporada', 'Capítulo final', 'Spoiler', 'Maratón', 'Personaje'],
    'Música': ['Guitarra', 'Coro', 'Playlist', 'Concierto', 'Micrófono', 'Batería'],
    'Karaoke': ['Micrófono', 'Letra', 'Desafinar', 'Dúo', 'Balada', 'Aplausos'],
    'Baile': ['Salsa', 'Coreografía', 'Pareja', 'Pista', 'Marinera', 'Paso prohibido'],
    'Cumpleaños': ['Velitas', 'Torta', 'Deseo', 'Regalo', 'Piñata', 'Sorpresa'],
    'Idiomas': ['Diccionario', 'Acento', 'Pronunciación', 'Traductor', 'Gramática'],
    'Programación': ['Bug', 'Teclado', 'Variable', 'Commit', 'Servidor', 'Café'],
    'Ciencia': ['Microscopio', 'Átomo', 'Hipótesis', 'Planeta', 'Fórmula', 'Probeta'],
    'Ajedrez': ['Jaque mate', 'Alfil', 'Torre', 'Enroque', 'Peón', 'Reloj'],
    'Esports': ['Final', 'Caster', 'Clutch', 'Patrocinador', 'Ranked', 'Draft'],
    'Rol': ['Dado de 20', 'Dragón', 'Hechizo', 'Taberna', 'Mazmorra', 'Personaje'],
    'Streaming': ['Directo', 'Chat', 'Suscriptor', 'Donación', 'Clip', 'Moderador'],
  };

  // ══════════════════════════════════════════════════════════════
  //  Retos para "Reto por inicial"
  // ══════════════════════════════════════════════════════════════

  static const List<String> _genericChallenges = [
    'cuenta un dato curioso sobre sí mismo',
    'imita a alguien famoso hasta que lo adivinen',
    'elige quién sigue y le propone un reto',
    'canta el coro de una canción',
    'cuenta su anécdota más divertida',
    'dice tres cosas que le gustan del plan',
    'hace la mejor cara de sorpresa del grupo',
  ];

  static const Map<String, List<String>> _challenges = {
    'Deportes': [
      'elige el calentamiento del grupo',
      'hace diez sentadillas',
      'cuenta su mejor anécdota deportiva',
      'propone el nombre del equipo',
      'imita la celebración de un deportista famoso',
      'reta a alguien a un mini duelo de equilibrio',
    ],
    'Comida': [
      'recomienda un plato que todos deberían probar',
      'describe su comida favorita sin decir su nombre',
      'elige el próximo lugar para comer',
      'cuenta su peor experiencia cocinando',
      'adivina un ingrediente con los ojos cerrados',
      'inventa el nombre de un plato con lo que hay en la mesa',
    ],
    'Naturaleza': [
      'propone una foto creativa para el grupo',
      'cuenta su viaje más memorable',
      'elige el próximo punto para explorar',
      'encuentra algo de color rojo en un minuto',
      'imita el sonido de un animal hasta que lo adivinen',
      'nombra cinco lugares del Perú que quiere conocer',
    ],
    'Chill': [
      'recomienda una película o serie en 20 segundos',
      'cuenta el último libro o serie que lo enganchó',
      'pone la próxima canción',
      'hace una reseña dramática del snack de la mesa',
      'cuenta qué haría con un día libre perfecto',
    ],
    'Juntas': [
      'propone un brindis',
      'baila diez segundos su paso favorito',
      'cuenta cómo conoció a alguien del grupo',
      'elige la siguiente canción',
      'imita al alma de la fiesta',
      'arma una foto grupal en menos de un minuto',
    ],
    'Académico': [
      'explica un concepto difícil en 30 segundos',
      'cuenta su mejor truco para estudiar',
      'propone la pregunta de examen más difícil',
      'resume su carrera o tema en tres palabras',
      'enseña una palabra en otro idioma',
    ],
    'Juegos online': [
      'cuenta su partida más épica',
      'elige el próximo juego del grupo',
      'imita el grito de victoria de su personaje',
      'confiesa su juego "culposo" favorito',
      'propone el nombre del clan para hoy',
    ],
  };

  // ══════════════════════════════════════════════════════════════
  //  Trivia
  // ══════════════════════════════════════════════════════════════

  static const List<TriviaQuestion> _genericTrivia = [
    TriviaQuestion('¿En qué región está Machu Picchu?',
        ['Puno', 'Cusco', 'Arequipa', 'Junín'], 1),
    TriviaQuestion('¿Cuál es el lago navegable más alto del mundo?',
        ['Titicaca', 'Junín', 'Poopó', 'Parinacochas'], 0),
    TriviaQuestion('¿Cuántos departamentos tiene el Perú?',
        ['20', '24', '25', '28'], 1,
        fact: 'Son 24, además de la Provincia Constitucional del Callao.'),
    TriviaQuestion('¿Qué ave aparece en el escudo nacional?',
        ['Cóndor', 'Vicuña', 'Ninguna', 'Gallito de las rocas'], 2,
        fact: 'El escudo tiene una vicuña, un árbol de quina y una cornucopia.'),
    TriviaQuestion('¿Qué día se celebra la Independencia del Perú?',
        ['28 de julio', '29 de junio', '8 de octubre', '30 de agosto'], 0),
    TriviaQuestion('¿Cuál es el río más largo que nace en el Perú?',
        ['Ucayali', 'Marañón', 'Amazonas', 'Rímac'], 2),
  ];

  static const Map<String, List<TriviaQuestion>> _trivia = {
    'Deportes': [
      TriviaQuestion('¿Cuántos jugadores tiene un equipo de fútbol en cancha?',
          ['9', '10', '11', '12'], 2),
      TriviaQuestion('¿En qué deporte el Perú ganó medalla olímpica en Seúl 1988?',
          ['Fútbol', 'Vóley', 'Tiro', 'Atletismo'], 1,
          fact: 'La selección femenina de vóley ganó la plata.'),
      TriviaQuestion('¿Cuánto mide una maratón?',
          ['21,1 km', '30 km', '42,195 km', '50 km'], 2),
      TriviaQuestion('¿Cuántos puntos vale un tiro detrás de la línea en básquet?',
          ['1', '2', '3', '4'], 2),
      TriviaQuestion('¿Cada cuántos años hay Juegos Olímpicos de verano?',
          ['2', '3', '4', '5'], 2),
      TriviaQuestion('¿Qué ciudad organizó los Juegos Panamericanos 2019?',
          ['Bogotá', 'Lima', 'Santiago', 'Quito'], 1),
      TriviaQuestion('¿Cuántos sets se necesitan ganar en un partido de vóley?',
          ['2', '3', '4', '5'], 1),
      TriviaQuestion('En tenis, ¿cómo se llama el marcador 40–40?',
          ['Ventaja', 'Deuce', 'Love', 'Tie-break'], 1),
    ],
    'Comida': [
      TriviaQuestion('¿Cuál es el ingrediente que "cocina" el pescado en el ceviche?',
          ['Vinagre', 'Limón', 'Sal', 'Ají'], 1),
      TriviaQuestion('¿De qué se hacen tradicionalmente los anticuchos?',
          ['Pollo', 'Corazón de res', 'Cerdo', 'Pescado'], 1),
      TriviaQuestion('¿Qué tubérculo es la base de la causa limeña?',
          ['Yuca', 'Camote', 'Papa amarilla', 'Olluco'], 2),
      TriviaQuestion('¿Con qué se tiñe la chicha morada?',
          ['Betarraga', 'Maíz morado', 'Uva', 'Arándano'], 1),
      TriviaQuestion('¿Qué fusión dio origen al chifa?',
          ['Peruano-japonesa', 'Peruano-china', 'Peruano-italiana', 'Peruano-árabe'], 1),
      TriviaQuestion('¿De qué masa se hacen los picarones?',
          ['Papa', 'Zapallo y camote', 'Yuca', 'Maíz'], 1),
      TriviaQuestion('¿Qué es la "leche de tigre"?',
          ['Un postre', 'El jugo del ceviche', 'Un trago', 'Una salsa de ají'], 1),
      TriviaQuestion('¿Cuántas variedades de papa nativa tiene el Perú, aproximadamente?',
          ['Unas 200', 'Unas 800', 'Más de 3000', 'Unas 50'], 2),
    ],
    'Naturaleza': [
      TriviaQuestion('¿Cuál es el ave nacional del Perú?',
          ['Cóndor andino', 'Gallito de las rocas', 'Colibrí', 'Pelícano'], 1),
      TriviaQuestion('¿Qué nevado es el más alto del Perú?',
          ['Huascarán', 'Ausangate', 'Misti', 'Salkantay'], 0),
      TriviaQuestion('¿Cuántos tipos de clima hay en el Perú según el SENAMHI?',
          ['8', '12', '27', '38'], 3),
      TriviaQuestion('¿Qué cañón es uno de los más profundos del mundo?',
          ['Colca', 'Cotahuasi', 'Del Pato', 'Sonche'], 1,
          fact: 'El Cotahuasi supera los 3500 m; el Colca le sigue muy de cerca.'),
      TriviaQuestion('¿Qué animal es un camélido silvestre?',
          ['Llama', 'Alpaca', 'Vicuña', 'Ninguno'], 2),
      TriviaQuestion('¿Cuál es la regla básica para dejar un campamento?',
          ['Enterrar la basura', 'No dejar rastro', 'Quemar todo', 'Dejar la leña'], 1),
      TriviaQuestion('¿Qué conviene hacer si te pierdes en un sendero?',
          ['Correr', 'Quedarte quieto y avisar', 'Separarte del grupo', 'Bajar por el río'], 1),
      TriviaQuestion('¿En qué región está la Reserva Nacional de Paracas?',
          ['Lima', 'Ica', 'Arequipa', 'Tacna'], 1),
    ],
    'Chill': [
      TriviaQuestion('¿Qué película peruana fue nominada al Oscar en 2010?',
          ['La teta asustada', 'Magallanes', 'Asu Mare', 'Contracorriente'], 0),
      TriviaQuestion('¿Quién escribió "La ciudad y los perros"?',
          ['César Vallejo', 'Mario Vargas Llosa', 'Ciro Alegría', 'José María Arguedas'], 1),
      TriviaQuestion('¿Cuántas casillas tiene un tablero de ajedrez?',
          ['36', '49', '64', '81'], 2),
      TriviaQuestion('¿Qué instrumento peruano se toca golpeándolo sentado encima?',
          ['Charango', 'Cajón', 'Quena', 'Zampoña'], 1),
      TriviaQuestion('¿Cuál de estos es un género musical peruano?',
          ['Chicha', 'Tango', 'Bachata', 'Vallenato'], 0),
      TriviaQuestion('¿Con cuántas piezas empieza cada jugador en ajedrez?',
          ['8', '12', '16', '20'], 2),
    ],
    'Juntas': [
      TriviaQuestion('¿Qué baile es considerado el baile nacional del Perú?',
          ['Huayno', 'Marinera', 'Festejo', 'Tondero'], 1),
      TriviaQuestion('¿En qué ciudad se celebra la Fiesta de la Candelaria?',
          ['Cusco', 'Puno', 'Cajamarca', 'Ayacucho'], 1),
      TriviaQuestion('¿Qué es la "hora loca"?',
          ['Un trago', 'Un momento de fiesta con disfraces', 'Un juego de cartas', 'Un baile típico'], 1),
      TriviaQuestion('¿Cuál es el trago bandera del Perú?',
          ['Chilcano', 'Pisco sour', 'Algarrobina', 'Capitán'], 1),
      TriviaQuestion('¿En qué mes es el carnaval de Cajamarca?',
          ['Enero', 'Febrero', 'Abril', 'Julio'], 1),
      TriviaQuestion('¿Quién canta "Cariñito" en su versión más conocida?',
          ['Los Hijos del Sol', 'Grupo 5', 'Agua Marina', 'Chacalón'], 0),
    ],
    'Académico': [
      TriviaQuestion('¿Cuál es el planeta más grande del sistema solar?',
          ['Saturno', 'Júpiter', 'Neptuno', 'Tierra'], 1),
      TriviaQuestion('¿Cuál es el símbolo químico del oro?',
          ['Ag', 'Au', 'Or', 'Go'], 1),
      TriviaQuestion('¿Cuántos bits tiene un byte?', ['4', '8', '16', '32'], 1),
      TriviaQuestion('¿Qué científico propuso la teoría de la relatividad?',
          ['Newton', 'Einstein', 'Tesla', 'Curie'], 1),
      TriviaQuestion('¿Qué universidad peruana fue fundada en 1551?',
          ['San Marcos', 'PUCP', 'UNI', 'San Agustín'], 0,
          fact: 'Es una de las universidades más antiguas de América.'),
      TriviaQuestion('¿Cuánto es 2 elevado a la 10?', ['512', '1000', '1024', '2048'], 2),
      TriviaQuestion('¿Qué idioma tiene más hablantes nativos en el mundo?',
          ['Inglés', 'Español', 'Chino mandarín', 'Hindi'], 2),
      TriviaQuestion('¿Qué gas absorben las plantas en la fotosíntesis?',
          ['Oxígeno', 'Dióxido de carbono', 'Nitrógeno', 'Helio'], 1),
    ],
    'Juegos online': [
      TriviaQuestion('¿En qué año salió Minecraft en su versión completa?',
          ['2009', '2011', '2014', '2016'], 1),
      TriviaQuestion('¿Cómo se llama el fontanero más famoso de Nintendo?',
          ['Luigi', 'Mario', 'Wario', 'Link'], 1),
      TriviaQuestion('¿Qué significa "GG" al final de una partida?',
          ['Go go', 'Good game', 'Great goal', 'Get gold'], 1),
      TriviaQuestion('¿Qué juego popularizó el modo Battle Royale masivo en 2017?',
          ['Fortnite', 'PUBG', 'Apex Legends', 'Free Fire'], 1),
      TriviaQuestion('¿Cuál es el nombre del protagonista de The Legend of Zelda?',
          ['Zelda', 'Link', 'Ganon', 'Epona'], 1),
      TriviaQuestion('¿Qué significa "AFK"?',
          ['Away from keyboard', 'All for kill', 'Attack fast kill', 'Auto free kick'], 0),
      TriviaQuestion('¿En qué juego compiten equipos de 5 por destruir el "Nexo"?',
          ['Dota 2', 'League of Legends', 'Valorant', 'Overwatch'], 1),
      TriviaQuestion('¿Qué consola vendió más unidades en la historia?',
          ['PlayStation 2', 'Nintendo Switch', 'Wii', 'Xbox 360'], 0),
    ],
  };

  // ══════════════════════════════════════════════════════════════
  //  Bingo de exploración (9 casillas por cartón)
  // ══════════════════════════════════════════════════════════════

  static const List<String> _genericBingo = [
    'Foto grupal', 'Alguien que llegó tarde', 'Un perro', 'Un mural',
    'Algo de color rojo', 'Un vendedor ambulante', 'Una risa contagiosa',
    'Alguien con lentes de sol', 'Un dato curioso', 'Un selfie con un desconocido',
    'Una canción que todos sepan', 'Un abrazo grupal',
  ];

  static const Map<String, List<String>> _bingo = {
    'Naturaleza': [
      'Un pájaro', 'Una flor amarilla', 'Una piedra con forma rara',
      'Huellas de animal', 'Un árbol enorme', 'Agua en movimiento',
      'Una mariposa', 'Una nube con forma', 'Una hoja más grande que tu mano',
      'Un mirador', 'Un insecto', 'Un hongo', 'Musgo', 'Una montaña nevada',
      'Un cartel del sendero', 'El atardecer',
    ],
    'Playa': [
      'Una concha', 'Un cangrejo', 'Un castillo de arena', 'Un surfista',
      'Una gaviota', 'Una sombrilla de colores', 'Un barco', 'Una ola grande',
      'Huellas en la arena', 'Un vendedor de raspadilla', 'Un pelícano',
      'Una estrella de mar',
    ],
    'Deportes': [
      'Un gol o punto de antología', 'Alguien que pide cambio',
      'Una botella de agua olvidada', 'Un choque de manos', 'Una barra',
      'Un estiramiento raro', 'Un árbitro improvisado', 'Una celebración épica',
      'Alguien sin aliento', 'Un tiro que pega en el palo',
    ],
    'Comida': [
      'Un plato con ají', 'Alguien que pide la receta', 'Un brindis',
      'Un postre compartido', 'Una foto a la comida', 'Alguien que repite plato',
      'Una salsa misteriosa', 'Un mozo muy amable', 'Una bebida morada',
      'Alguien que no puede con el picante',
    ],
    'Juntas': [
      'Alguien bailando solo', 'Una canción de cumbia', 'Un brindis improvisado',
      'Una foto con flash', 'Alguien cantando a todo pulmón', 'Un trencito',
      'Un disfraz', 'Alguien que llega con regalo', 'Un abrazo grupal',
      'Una anécdota vergonzosa',
    ],
  };

  // ══════════════════════════════════════════════════════════════
  //  ¿Qué prefieres?
  // ══════════════════════════════════════════════════════════════

  static const List<(String, String)> _genericWyr = [
    ('Viajar al pasado', 'Viajar al futuro'),
    ('No volver a usar redes sociales', 'No volver a ver series'),
    ('Vivir en la playa', 'Vivir en la sierra'),
    ('Saber todos los idiomas', 'Tocar todos los instrumentos'),
    ('Ser invisible', 'Poder volar'),
    ('Un viaje sorpresa', 'Un viaje planeado al detalle'),
  ];

  static const Map<String, List<(String, String)>> _wyr = {
    'Comida': [
      ('Ceviche toda la vida', 'Lomo saltado toda la vida'),
      ('Solo dulce', 'Solo salado'),
      ('Cocinar siempre', 'Lavar siempre los platos'),
      ('Chifa un lunes', 'Pollo a la brasa un domingo'),
      ('Comer sin ají', 'Comer todo con rocoto'),
      ('Desayuno de campeones', 'Cena de lujo'),
    ],
    'Naturaleza': [
      ('Acampar en la sierra', 'Acampar en la playa'),
      ('Ver un cóndor', 'Ver delfines'),
      ('Subir una montaña', 'Bajar un río en kayak'),
      ('Sin linterna una noche', 'Sin agua una tarde'),
      ('Amanecer en la cima', 'Atardecer en el mar'),
    ],
    'Chill': [
      ('Una película mala con amigos', 'Una buena solo'),
      ('Leer el libro', 'Ver la serie'),
      ('Spoilers de todo', 'No ver el final de nada'),
      ('Playlist de los 80', 'Playlist de reguetón'),
      ('Domingo de lluvia', 'Domingo de sol'),
    ],
    'Juntas': [
      ('Organizar la fiesta', 'Ser el invitado sorpresa'),
      ('Bailar toda la noche', 'Cantar toda la noche'),
      ('Fiesta temática', 'Fiesta improvisada'),
      ('Saber todos los pasos', 'Saber todas las letras'),
    ],
    'Deportes': [
      ('Ganar la final por penales', 'Golear 5–0 en primera fase'),
      ('Ser el capitán', 'Ser el goleador'),
      ('Correr una maratón', 'Escalar un nevado'),
      ('Entrenar al amanecer', 'Entrenar de noche'),
    ],
    'Académico': [
      ('Examen oral', 'Examen escrito'),
      ('Estudiar en grupo', 'Estudiar solo'),
      ('Exponer primero', 'Exponer último'),
      ('Dominar programación', 'Dominar un idioma nuevo'),
    ],
    'Juegos online': [
      ('Ganar siempre con lag', 'Perder sin lag'),
      ('Jugar solo competitivo', 'Jugar solo casual'),
      ('Un juego para siempre', 'Un juego nuevo cada semana'),
      ('Ser soporte', 'Ser carry'),
    ],
  };

  // ══════════════════════════════════════════════════════════════
  //  ¿Quién es más probable que…?
  // ══════════════════════════════════════════════════════════════

  static const List<String> _genericMostLikely = [
    'llegue tarde al próximo plan',
    'se haga viral sin querer',
    'termine organizando todo',
    'se quede dormido en el camino',
    'haga amistad con un desconocido hoy',
    'cuente un chiste malo y se ría solo',
    'pierda algo antes de que acabe el día',
  ];

  static const Map<String, List<String>> _mostLikely = {
    'Comida': [
      'pida lo más picante de la carta',
      'termine comiendo del plato de otro',
      'le tome foto a todo antes de comer',
      'pida la receta al cocinero',
      'diga "yo invito" y luego se arrepienta',
    ],
    'Juntas': [
      'sea el último en irse de la fiesta',
      'arme la hora loca',
      'cante más fuerte en el karaoke',
      'termine bailando con desconocidos',
      'organice la próxima reunión',
    ],
    'Chill': [
      'se quede dormido en la película',
      'haga spoiler sin querer',
      'tenga una playlist para cada ocasión',
      'lea tres libros a la vez',
    ],
    'Deportes': [
      'pida cambio a los cinco minutos',
      'reclame todas las faltas',
      'llegue con el uniforme completo',
      'meta autogol',
    ],
  };

  // ══════════════════════════════════════════════════════════════
  //  Debate exprés
  // ══════════════════════════════════════════════════════════════

  static const List<String> _genericDebate = [
    '¿Es mejor la playa en invierno que en verano?',
    '¿La piña va en la pizza?',
    '¿Es mejor madrugar o trasnochar?',
    '¿Hay que contestar los mensajes al toque?',
  ];

  static const Map<String, List<String>> _debate = {
    'Académico': [
      '¿La inteligencia artificial ayuda o perjudica al aprendizaje?',
      '¿Deberían eliminarse los exámenes finales?',
      '¿Es mejor estudiar de noche o de día?',
      '¿Las clases virtuales son tan buenas como las presenciales?',
      '¿Aprender a programar debería ser obligatorio en el colegio?',
      '¿Es más útil aprender inglés o chino?',
      '¿El trabajo en grupo debería calificarse individualmente?',
    ],
    'Juegos online': [
      '¿Los videojuegos son un deporte?',
      '¿Es mejor jugar en PC o en consola?',
      '¿Las microtransacciones arruinan los juegos?',
      '¿Un buen juego necesita buena historia?',
    ],
  };

  // ══════════════════════════════════════════════════════════════
  //  Resolución
  // ══════════════════════════════════════════════════════════════

  /// Contenido para una actividad con la categoría [category] tal como la
  /// guarda la base: "Deportes,Fútbol", "Fútbol" o "Comida".
  static GamePack forCategory(String? category) {
    final raw = category ?? '';
    final main = CategoryConstants.mainCategoryOf(raw);
    final sub = _subcategoryOf(raw, main);

    List<T> merged<T>(Map<String, List<T>> source, List<T> generic) {
      final result = <T>[
        ...?source[sub],
        ...?source[main],
      ];
      // Un mínimo de variedad: si la categoría tiene poco contenido, se
      // completa con el genérico.
      if (result.length < 8) {
        result.addAll(generic.where((item) => !result.contains(item)));
      }
      return List.unmodifiable(result);
    }

    return GamePack(
      mainCategory: main,
      subcategory: sub,
      impostorWords: merged(_words, _genericWords),
      initialChallenges: merged(_challenges, _genericChallenges),
      trivia: merged(_trivia, _genericTrivia),
      bingo: merged(_bingo, _genericBingo),
      wouldYouRather: merged(_wyr, _genericWyr),
      mostLikely: merged(_mostLikely, _genericMostLikely),
      debateTopics: merged(_debate, _genericDebate),
      featured: List.unmodifiable(_featured[main] ?? _genericFeatured),
    );
  }

  /// Primera subcategoría reconocida que pertenezca a [main].
  static String? _subcategoryOf(String raw, String? main) {
    if (main == null) return null;
    final subs = CategoryConstants.groups[main] ?? const <String>[];
    for (final part in raw.split(',').map((p) => p.trim().toLowerCase())) {
      for (final sub in subs) {
        if (sub.toLowerCase() == part) return sub;
      }
    }
    return null;
  }
}
