/**
 * French translations. Two dictionaries:
 *  - `content`: keyed by the stable `id` already on every data-driven object
 *    (enemies, weapons, abilities, upgrades, permanent upgrades, zones,
 *    unlocks, synergies, world events/options) — looked up via `tc(id, field, fallback)`.
 *  - `ui`: flat semantic keys for everything else (menus, HUD, buttons,
 *    toasts, onboarding, settings...) — looked up via `t(key, fallback)`.
 *
 * "Ember" is kept untranslated throughout, deliberately: it's the game's
 * central lore proper noun (the last light itself — Ember Blade, Ember
 * Burst, Ember Sight, Ember Citadel, the Embers currency...), not an
 * ordinary word, the same way "the Force" or a invented in-fiction term
 * usually stays put across a localization rather than being translated
 * per-occurrence. "Cinder" (a different, ordinary word in the English text —
 * Cinder Wraith, Cinder Wound) is translated normally as "Cendre".
 */

export const FR_CONTENT: Record<string, Record<string, string>> = {
  // ---------- Enemies ----------
  ashCrawler: { name: 'Rampant Cendré', description: 'Une carcasse frétillante de cendre et de griffes. Rapide, fragile, chasse en meute.' },
  hollow: { name: 'Creux', description: 'Une lente carcasse boursouflée, ce qu’il reste d’une personne restée trop longtemps dans le noir.' },
  flameWisp: { name: 'Feu Follet', description: 'Un esprit-braise à la dérive qui frappe de traits de lumière mourante.' },
  gravebound: { name: 'Hanteur de Tombe', description: 'Muscle ressuscité et fer rouillé. Lent à frapper, ravageur au contact.' },
  shadowStalker: { name: 'Traqueur des Ombres', description: 'Un éclat d’obscurité affamée. Disparaît, se repositionne, frappe par derrière.' },
  emberDevourer: { name: 'Dévoreur d’Ember', description: 'Une abomination d’élite qui se repaît de lumière mourante. Frappe fort, frappe souvent.' },
  cinderWraith: { name: 'Spectre de Cendre', description: 'Une horreur des profondeurs réveillée par la lumière déclinante de l’Ember. Traverse les coups.' },
  blightbloat: {
    name: 'Boursouflé Fétide',
    description:
      'Un Creux si gorgé des spores des ruines que son corps est devenu un sac gonflé et luminescent. Il veut être près de vous quand il éclate.',
  },
  hollowWarden: {
    name: 'Gardien Creux',
    description:
      'Les derniers soldats du guet en ruines. Son bouclier est la porte qu’il est mort à garder — rien ne passe par l’avant. Contournez-le, ou punissez sa charge.',
  },
  sunkenWarden: {
    name: 'Le Gardien Englouti',
    description: 'Capitaine du guet noyé, tenant toujours une ligne tombée il y a cent ans. Brisez le bouclier, puis brisez l’homme.',
  },
  ashenColossus: {
    name: 'Le Colosse de Cendre',
    description: 'Ce qu’il reste du premier Gardien, fusionné à la corruption qu’il avait juré de contenir.',
  },

  // ---------- Weapons ----------
  emberBlade: {
    name: 'Lame d’Ember',
    description: 'Une épée courte équilibrée, réchauffée par un éclat de la dernière lumière. Fiable en toute circonstance.',
  },
  voidScythe: { name: 'Faux du Vide', description: 'Une lame pesante qui boit l’élan. Lente, mais chaque coup est un verdict.' },
  solarSpear: { name: 'Lance Solaire', description: 'Une lance de lumière durcie. Transperce la foule visée.' },

  // ---------- Abilities ----------
  emberBurst: {
    name: 'Éclat d’Ember',
    description: 'Libère l’Ember en une floraison violente de lumière, brûlant et repoussant tout ce qui est proche.',
  },
  stormstep: { name: 'Pas de l’Orage', description: 'Traverse l’obscurité en un éclair de vitesse, fauchant tout sur son passage.' },
  wardingSigil: {
    name: 'Sceau de Protection',
    description: 'Plante un sceau de la dernière lumière qui soigne vos blessures et brûle les corrompus.',
  },

  // ---------- Upgrades (common -> legendary) ----------
  'weathered-grip': { name: 'Prise Usée', description: '+10% dégâts.' },
  'quick-stride': { name: 'Foulée Rapide', description: '+8% vitesse de déplacement.' },
  'hearty-vigor': { name: 'Vigueur Robuste', description: '+18 PV maximum.' },
  'sharp-focus': { name: 'Concentration Aiguisée', description: '+4% chances de critique.' },
  'ember-sense': { name: 'Instinct d’Ember', description: '+15% d’Embers gagnés.' },
  'loose-satchel': { name: 'Sacoche Ample', description: '+30 portée de ramassage.' },
  'steady-breath': { name: 'Souffle Stable', description: '+20 endurance maximum.' },
  'brisk-hands': { name: 'Mains Vives', description: '+12% vitesse d’attaque.' },
  'honed-edge': { name: 'Tranchant Aiguisé', description: '+15% dégâts.' },
  'hardened-hide': { name: 'Peau Endurcie', description: '+8% réduction des dégâts.' },
  'killing-instinct': { name: 'Instinct Meurtrier', description: '+25% dégâts critiques.' },
  featherstep: { name: 'Pas de Plume', description: '-15% recharge d’esquive.' },
  'embered-veins': { name: 'Veines d’Ember', description: '+20% dégâts de compétence.' },
  'cinder-wound': { name: 'Blessure Cendrée', description: '+10% de chances d’enflammer les ennemis au contact.' },
  'iron-lungs': { name: 'Poumons de Fer', description: '+35 endurance maximum.' },
  'ember-wellspring': { name: 'Source d’Ember', description: '+18% régénération d’énergie de compétence.' },
  'twin-embers': { name: 'Embers Jumeaux', description: '+1 projectile sur les attaques à distance et les compétences.' },
  'wide-blast': { name: 'Explosion Large', description: '+20% dégâts et rayon de zone.' },
  'leeching-strikes': { name: 'Frappes Vampiriques', description: '+5% de vol de vie sur tous les dégâts infligés.' },
  'warding-glow': { name: 'Lueur Protectrice', description: '+1 charge de bouclier qui bloque le prochain coup.' },
  'shadow-step': { name: 'Pas de l’Ombre', description: '+18% vitesse d’attaque, silencieux comme l’obscurité.' },
  'reckless-vigor': { name: 'Vigueur Téméraire', description: '+28% dégâts, -10 PV maximum. Le pouvoir a un prix.' },
  'blood-focus': { name: 'Concentration Sanglante', description: '+10% chances de critique, +20% dégâts critiques.' },
  'phoenix-heart': { name: 'Cœur de Phénix', description: '+2 régénération de PV par seconde, +20 PV maximum.' },
  'warden-ascendant': { name: 'Gardien Ascendant', description: '+40% dégâts, +40% puissance d’Ember.' },
  'last-light': { name: 'La Dernière Lumière', description: '+2 charges de bouclier, +15% réduction des dégâts, +10% vol de vie.' },

  // ---------- Permanent upgrades (Soul Ash) ----------
  'wardens-resolve': { name: 'Résolution du Gardien', description: '+10 PV maximum de départ par niveau.' },
  'ember-edge': { name: 'Tranchant d’Ember', description: '+5% dégâts de départ par niveau.' },
  'swift-boots': { name: 'Bottes Agiles', description: '+12 vitesse de déplacement par niveau.' },
  'fortunes-favor': { name: 'Faveur de la Fortune', description: '+5% de chances d’améliorations de rareté supérieure par niveau.' },
  'ember-hoard': { name: 'Trésor d’Ember', description: '+8% d’Embers gagnés par niveau.' },
  'second-wind': { name: 'Second Souffle', description: '+1,2 régénération d’énergie par seconde par niveau.' },
  'iron-skin': { name: 'Peau de Fer', description: '+3% réduction des dégâts par niveau.' },
  'keen-eye': { name: 'Œil Perçant', description: '+3% chances de critique par niveau.' },
  'vital-embers': { name: 'Embers Vitaux', description: '+0,3 régénération de PV par seconde par niveau.' },
  'endless-vigor': { name: 'Vigueur Sans Fin', description: '+8 endurance maximum de départ par niveau.' },
  'deep-pockets': { name: 'Poches Profondes', description: '+20 portée de ramassage et +1 charge de bouclier par niveau.' },

  // ---------- Zones ----------
  ashenWoods: { name: 'Bois de Cendre', subtitle: 'Où les arbres se souviennent du feu' },
  hollowRuins: { name: 'Les Ruines Creuses', subtitle: 'La pierre se souvient de ce que la chair oublie' },
  emberCitadel: { name: 'Citadelle d’Ember', subtitle: 'La dernière lumière brûle derrière ces murs' },

  // ---------- Unlocks (the Armory) ----------
  'unlock-void-scythe': { name: 'Faux du Vide', description: 'Débloquez une arme de mêlée lente et dévastatrice.' },
  'unlock-solar-spear': { name: 'Lance Solaire', description: 'Débloquez une arme à distance perforante.' },
  'unlock-stormstep': { name: 'Pas de l’Orage', description: 'Débloquez une compétence de ruée éclair.' },
  'unlock-warding-sigil': { name: 'Sceau de Protection', description: 'Débloquez une compétence de totem défensif.' },
  awakenDeep: {
    name: 'Éveiller les Profondeurs',
    description: 'Quelque chose remue. Le Spectre de Cendre hante désormais les ruines et la citadelle.',
  },
  emberSight: {
    name: 'Vision d’Ember',
    description: 'Voyez plus loin dans ce que l’Ember pourrait devenir. Les améliorations légendaires peuvent désormais apparaître.',
  },

  // ---------- Synergies ----------
  emberCritical: {
    name: 'Ember & Critique',
    description: 'Les coups critiques ont une chance de faire détoner la cible en une explosion de lumière d’Ember.',
  },
  ashFire: { name: 'Cendre & Feu', description: 'Les ennemis en feu subissent 40% de dégâts supplémentaires de toutes sources.' },
  shadowDodge: { name: 'Ombre & Esquive', description: 'Une esquive parfaitement chronométrée accorde une brève montée de dégâts.' },
  lightHealing: {
    name: 'Lumière & Soin',
    description: 'Les ennemis tués en brûlant ou sous protection ont une chance de lâcher une motte de soin.',
  },
  wrath: { name: 'Courroux du Gardien', description: 'Moins vous avez de PV, plus vous infligez de dégâts — jusqu’à +50% au bord de la mort.' },

  // ---------- World events ----------
  oldShrine: { title: 'L’Ancien Sanctuaire', description: 'Un autel noirci vibre de la lumière qui lui reste. Il offre une unique bénédiction.' },
  'blessing-embers': { label: 'Bienfait d’Ember', detail: 'Recevez une généreuse poignée d’Embers.' },
  'blessing-hp': { label: 'Merci de la Lumière', detail: 'Soignez entièrement vos blessures.' },

  forgottenMerchant: {
    title: 'Le Marchand Oublié',
    description: 'Une silhouette encapuchonnée commerce en choses mieux laissées enterrées. « Tout a un prix, Gardien. »',
  },
  'buy-upgrade-cheap': { label: 'Un Charme Modeste', detail: 'Amélioration garantie, chances communes. 30 Embers.' },
  'buy-upgrade-rare': { label: 'Une Relique Rare', detail: 'Amélioration rare ou mieux garantie. 70 Embers.' },
  'leave-merchant': { label: 'Refuser', detail: 'Certains prix ne valent pas d’être payés.' },

  dyingFlame: {
    title: 'La Flamme Mourante',
    description: 'Une flamme vacillante vous offre de la force, mais le feu réclame du combustible — et vous êtes le seul combustible ici.',
  },
  'sacrifice-hp': { label: 'Offrir Votre Sang', detail: 'Perdez 25% de vos PV actuels pour une amélioration rare ou mieux.' },
  'refuse-flame': { label: 'S’éloigner', detail: 'La flamme vacille et s’éteint. Rien de tenté.' },

  theWhisper: {
    title: 'Le Murmure',
    description: 'Quelque chose dans le noir prononce votre nom. Cela sait ce que vous portez. Cela veut jouer à un jeu.',
  },
  'gamble-embers': { label: 'Miser Vos Embers', detail: 'Pile ou face : doublez vos Embers, ou perdez-en la moitié.' },
  'ignore-whisper': { label: 'L’Ignorer', detail: 'Certaines voix sont mieux laissées sans réponse. Léger gain d’Embers.' },

  wardensOath: {
    title: 'Le Serment du Gardien',
    description:
      'Un gardien de pierre s’agenouille devant un bouclier fissuré, ses lèvres encore figées sur le dernier mot d’un serment. « Tenez la ligne. »',
  },
  'take-oath': { label: 'Reprendre le Serment', detail: 'Recevez la protection d’un Gardien : une charge de bouclier supplémentaire.' },
  'pry-shield': {
    label: 'Arracher le Bouclier',
    detail: 'Recevez 55 Embers. La poigne de la statue vous broie les côtes au passage : perdez 15% de vos PV.',
  },
  'leave-warden': { label: 'Le Laisser s’Agenouiller', detail: 'Certains serments ne sont pas les vôtres à porter.' },

  sporeMother: {
    title: 'La Mère des Spores',
    description:
      'Une masse fongique pulsante emplit l’alcôve, respirant lentement. Ce dont elle a poussé est encore là-dedans, et ce n’est pas tout à fait mort.',
  },
  'breathe-deep': { label: 'Respirer Profondément', detail: 'Les spores prennent racine en vous. Gagnez +15 PV maximum pour cette run, et soignez 15.' },
  'cut-it-open': {
    label: 'L’Éventrer',
    detail: 'Perdez 20% de vos PV actuels dans l’explosion, et prenez ce qu’elle faisait pousser : une amélioration rare ou mieux.',
  },
  'leave-mother': { label: 'Reculer', detail: 'Laissez-la respirer. Léger gain d’Embers depuis le sol.' },

  emberWell: {
    title: 'Le Puits d’Ember',
    description: 'Un puits enfoncé profondément dans le noir, luisant faiblement. Les Embers déposés ici ne reviennent pas — mais le puits se souvient.',
  },
  'feed-well': { label: 'Nourrir le Puits', detail: 'Dépensez 40 Embers pour tirer une mesure de Cendre d’Âme, conservée même si vous tombez.' },
  'leave-well': { label: 'Le Laisser Tranquille', detail: 'Le puits peut attendre. Vous aussi.' },
};

/** Flat UI-chrome strings (menus, HUD, buttons, toasts, onboarding, settings...). */
export const FR_UI: Record<string, string> = {
  // Rarities
  'rarity.common': 'Commune',
  'rarity.uncommon': 'Peu commune',
  'rarity.rare': 'Rare',
  'rarity.epic': 'Épique',
  'rarity.legendary': 'Légendaire',
  // Currencies
  'currency.embers': 'Embers',
  'currency.soulAsh': 'Cendre d’Âme',
  // Room type labels
  'room.start': 'Entrée',
  'room.combat': 'Combat',
  'room.elite': 'Antre d’Élite',
  'room.chest': 'Chambre Forte',
  'room.shop': 'Marchand',
  'room.event': 'Inconnu',
  'room.rest': 'Répit',
  'room.heart': 'Cœur de Zone',
  'room.boss': 'Le Colosse',
  'room.sanctum': 'Sanctuaire Noyé',
  // Phase / event banners
  'banner.phase': 'PHASE',
  'banner.riteBegins': 'LE RITE COMMENCE',
  'banner.wave': 'VAGUE',
  'banner.riteDone': 'LE RITE EST ACCOMPLI',
  'banner.shieldShatters': 'LE BOUCLIER SE BRISE',
  // Enemy display-name templates ({name} is replaced with the already-translated base name)
  'enemy.empoweredFormat': '{name} Renforcé',
  'enemy.heartWardenFormat': '{name}, Gardien du Cœur',
  'enemy.mutatedFormat': '{name}, Marqué par l’Ember',
  'hud.rmbHint': 'Clic D.',
  // Onboarding hints
  'hint.desktop.move': 'Utilisez <strong>ZQSD</strong> pour vous déplacer — visez avec la souris.',
  'hint.desktop.attack': '<strong>Clic Gauche</strong> pour frapper avec votre arme.',
  'hint.desktop.ability': '<strong>Clic Droit</strong> déclenche Éclat d’Ember une fois chargé.',
  'hint.desktop.dodge': '<strong>Espace</strong> pour esquiver. Brièvement invulnérable — chronométrez bien votre geste.',
  'hint.desktop.interact': 'Appuyez sur <strong>E</strong> pour ouvrir, ramasser, ou activer ce qui est à proximité.',
  'hint.touch.move': 'Faites glisser le stick gauche pour vous déplacer — votre Gardien vise où vous marchez.',
  'hint.touch.attack': 'Appuyez sur le bouton <strong>lame</strong> pour frapper avec votre arme.',
  'hint.touch.ability': 'Appuyez sur le bouton <strong>ember</strong> pour déclencher Éclat d’Ember une fois chargé.',
  'hint.touch.dodge': 'Appuyez sur le bouton <strong>esquive</strong>. Brièvement invulnérable — chronométrez bien votre geste.',
  'hint.touch.interact': 'Appuyez sur le bouton <strong>E</strong> pour ouvrir, ramasser, ou activer ce qui est à proximité.',
  'hint.shared.upgrade': 'Choisissez une bénédiction — vous ne pouvez en prendre qu’une par offre.',
  'hint.shared.chest': 'Les coffres contiennent une amélioration garantie. Coffres plus rares, meilleures chances.',
  'hint.shared.shop': 'Dépensez vos Embers ici en améliorations, soins, ou relance.',
  'hint.shared.corruption': 'Plus une zone s’éternise, plus l’obscurité grandit. Continuez d’avancer.',
  'hint.shared.boss': 'Guettez la lueur rouge avant qu’une attaque ne touche — c’est votre fenêtre pour esquiver.',
  'hint.shared.stairs': 'Le chemin vers le bas est ouvert. Il n’y a pas de retour possible.',
  'hint.shared.warden': 'Le bouclier d’un Gardien dévie les coups venant de face. Contournez-le — ou frappez quand sa garde tombe après une charge.',
  'hint.shared.bloat': 'Les Boursouflés explosent. Reculez quand l’un d’eux gonfle, et évitez les spores qu’il laisse derrière lui.',
  'hint.shared.sanctum': 'Un rite sommeille ici. Agenouillez-vous au cercle pour l’éveiller — les portes se scelleront jusqu’à ce que chaque vague soit vaincue.',
  // Main menu
  'menu.seedPlaceholder': 'Graine (optionnel)',
  'menu.seedAriaLabel': 'Graine de la partie',
  'menu.play': 'Jouer',
  'menu.upgrades': 'Améliorations',
  'menu.armory': 'Armurerie',
  'menu.settings': 'Paramètres',
  'menu.credits': 'Crédits',
  'menu.tagline': 'L’Ember se meurt. Quelqu’un doit porter la dernière lumière.',
  // Loadout select
  'loadout.begin': 'Commencer',
  'loadout.title': 'Choisissez Votre Équipement',
  'loadout.weapon': 'Arme',
  'loadout.ability': 'Compétence',
  // Upgrade select
  'upgradeSelect.title': 'Une Bénédiction Vous Attend',
  'upgradeSelect.subtitle': 'Choisissez-en une. L’Ember se souvient de chaque choix.',
  // Shop
  'shop.reroll': 'Relancer',
  'shop.title': 'Le Marchand Oublié',
  'shop.subtitle': '« Tout a un prix, Gardien. Choisissez sagement. »',
  'shop.leave': 'Partir',
  'shop.healName': 'Soigner Vos Blessures',
  'shop.healDesc': 'Restaure une partie de vos points de vie.',
  'shop.sold': 'Vendu',
  'shop.buy': 'Acheter',
  // World event choice cost
  'event.costsPrefix': 'Coûte',
  // Pause menu
  'pause.title': 'Pause',
  'pause.resume': 'Reprendre',
  'pause.yourBuild': 'Votre Build',
  'pause.abandonRun': 'Abandonner la Run',
  'pause.activeSynergies': 'Synergies actives',
  'pause.noSynergies': 'Aucune synergie active pour l’instant — certaines paires d’améliorations débloquent un effet bonus.',
  'pause.upgradeCountOne': '{count} amélioration récoltée cette run',
  'pause.upgradeCountMany': '{count} améliorations récoltées cette run',
  'pause.noUpgrades': 'Aucune amélioration pour l’instant — nettoyez une salle, ouvrez un coffre, ou visitez une boutique.',
  'pause.back': 'Retour',
  'pause.abandonConfirmTitle': 'Abandonner cette run ?',
  'pause.abandonConfirmBody': 'L’Ember s’éteindra ici. Toute la progression de cette run sera perdue — seule la Cendre d’Âme déjà mise de côté sera conservée.',
  'pause.keepGoing': 'Continuer',
  'pause.abandonConfirm': 'Abandonner',

  // Player level / XP / stat points
  'banner.levelUp': 'NIVEAU',
  'toast.statPointOne': 'Un nouveau point de caractéristique est disponible — appuyez sur {key} pour ouvrir votre personnage.',
  'toast.statPointMany': '{count} points de caractéristique sont disponibles — appuyez sur {key} pour ouvrir votre personnage.',
  'upgrade.level': 'Niveau',
  'inventory.tabCharacter': 'Personnage',
  'inventory.tabBuild': 'Build',
  'inventory.title': 'Personnage',
  'inventory.player': 'JOUEUR',
  'inventory.levelFormat': 'Niveau {n}',
  'inventory.pointsAvailableFormat': '{count} point(s) de caractéristique disponible(s)',
  'inventory.perLevelFormat': '{value} par niveau',
  'stat.hp': 'PV',
  'stat.m1Damage': 'Dégâts M1',
  'stat.stamina': 'Endurance',
  'stat.abilityDamage': 'Dégâts de Compétence',
  'stat.range': 'Portée',
  'stat.moveSpeed': 'Vitesse de Déplacement',
  'stat.attackSpeed': 'Vitesse d’Attaque',
  'stat.unit.hp': 'PV',
  'stat.unit.stamina': 'Endurance',
  'stat.unit.moveSpeed': 'Vitesse',
  'hud.levelAbbrevFormat': 'Niv.{n}',
  'hud.pointsReadyFormat': '+{count}',
  // Reward popup source labels
  'reward.merchant': 'Le Marchand',
  'reward.chest': 'Récompense du Coffre',
  // Victory / defeat screens
  'victory.title': 'L’Ember Perdure',
  'victory.subtitle': 'Le Colosse de Cendre tombe. Pour l’instant, l’obscurité recule.',
  'victory.continue': 'Continuer',
  'defeat.title': 'La Lumière Vacille et s’Éteint',
  'defeat.subtitleFormat': 'Tombé dans {zone}. L’Ember faiblit, mais ne meurt pas.',
  'defeat.tryAgain': 'Réessayer',
  'defeat.mainMenu': 'Menu Principal',
  'endScreen.seedLabel': 'Graine',
  'stat.time': 'Temps',
  'stat.timeSurvived': 'Temps de Survie',
  'stat.kills': 'Éliminations',
  'stat.damageDealt': 'Dégâts Infligés',
  'stat.embersCollected': 'Embers Récoltés',
  'stat.upgradesTaken': 'Améliorations Prises',
  'stat.soulAshEarned': 'Cendre d’Âme Gagnée',
  // Meta-progression menu (permanent upgrades / armory)
  'meta.permanentUpgrades': 'Améliorations Permanentes',
  'meta.upgradesSubtitle': 'Dépensez la Cendre d’Âme récoltée au fil des runs tombées pour renforcer chaque futur Gardien.',
  'meta.armorySubtitle': 'Débloquez de nouvelles armes, compétences et menaces qui persistent à travers chaque run.',
  'meta.locked': 'Verrouillé',
  'meta.max': 'Max',
  'meta.requiresFormat': 'Nécessite {name}',
  'meta.unlocked': 'Débloqué',
  // Credits
  'credits.about': 'Un action-roguelite dark fantasy autonome. Chaque sprite, particule et son de ce jeu est généré procéduralement à l’exécution — aucun fichier d’art ou audio externe.',
  'credits.tech': 'Conçu avec TypeScript, Vite, Canvas 2D, et la Web Audio API.',
  'credits.thanks': 'Merci de garder la dernière lumière.',
  // Settings menu
  'settings.language': 'Langue',
  'settings.languageHint': 'Recharge le jeu pour appliquer',
  'settings.masterVolume': 'Volume Général',
  'settings.musicVolume': 'Volume de la Musique',
  'settings.sfxVolume': 'Volume des Effets Sonores',
  'settings.muteAll': 'Tout Couper',
  'settings.muteAllHint': 'Coupe toute la sortie audio',
  'settings.screenShake': 'Tremblement d’Écran',
  'settings.screenShakeHint': 'Secousse de caméra lors des impacts lourds',
  'settings.particles': 'Particules',
  'settings.graphicsQuality': 'Qualité Graphique',
  'settings.quality.low': 'Faible',
  'settings.quality.medium': 'Moyen',
  'settings.quality.high': 'Élevé',
  'settings.textSize': 'Taille du Texte',
  'settings.highContrast': 'Contraste Élevé',
  'settings.highContrastHint': 'Augmente le contraste du texte et de l’interface',
  'settings.reducedMotion': 'Mouvement Réduit',
  'settings.reducedMotionHint': 'Minimise les animations de l’interface',
  'settings.fullscreen': 'Plein Écran',
  'settings.toggle': 'Basculer',
  'settings.done': 'Terminé',
  // Mobile orientation lock
  'orientation.rotate': 'Faites pivoter votre appareil en mode paysage pour une meilleure expérience',
  // Misc gameplay toasts
  'toast.wardenWard': 'La protection d’un Gardien se referme sur vous.',
  'toast.brazier': 'La chaleur du brasero soigne vos blessures.',
  'toast.sealOpen': 'Le sceau grince et s’ouvre. Les marches mènent vers le bas.',
  'toast.sanctumReward': 'Le sanctuaire livre ce qu’il gardait : une bénédiction rare, et 35 Embers.',
  'hud.synergyFormed': 'Synergie Formée',
  // Room interaction prompts
  'interact.openChest': 'Ouvrir le Coffre',
  'interact.browseWares': 'Voir la Marchandise',
  'interact.investigate': 'Examiner',
  'interact.restAtBrazier': 'Se Reposer au Brasero',
  'interact.kneelAtCircle': 'S’Agenouiller au Cercle',
  'interact.theNextZone': 'la zone suivante',
  'interact.descendToFormat': 'Descendre vers {name}',
};
