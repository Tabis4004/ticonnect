-- =====================================================================
-- 07_seed.sql — Référentiel métiers et emplacements publicitaires
-- Métiers calibrés pour le marché ouest / centre-africain francophone.
-- =====================================================================

insert into public.trade_categories (slug, name_fr, icon, sort_order) values
  ('batiment',      'Bâtiment & Construction', 'hard-hat',   1),
  ('transport',     'Transport & Livraison',   'truck',      2),
  ('maison',        'Maison & Entretien',      'home',       3),
  ('reparation',    'Réparation & Technique',  'wrench',     4),
  ('espaces-verts', 'Jardinage & Agriculture', 'sprout',     5),
  ('securite',      'Sécurité & Gardiennage',  'shield',     6),
  ('artisanat',     'Artisanat & Confection',  'scissors',   7),
  ('evenementiel',  'Événementiel & Service',  'party-popper', 8);

-- ---------------------------------------------------------------------
-- MÉTIERS
-- search_terms contient les appellations locales et les fautes courantes,
-- exploitées par la recherche floue (pg_trgm).
-- ---------------------------------------------------------------------
insert into public.trades (category_id, slug, name_fr, search_terms, sort_order)
select c.id, v.slug, v.name_fr, v.search_terms, v.sort_order
from (values
  -- Bâtiment
  ('batiment', 'macon',              'Maçon',                     'macon maçon mason briqueteur maconnerie', 1),
  ('batiment', 'coffreur-ferrailleur','Coffreur-ferrailleur',     'coffreur ferrailleur ferraille armature', 2),
  ('batiment', 'carreleur',          'Carreleur',                 'carreleur carrelage carreaux faience', 3),
  ('batiment', 'peintre-batiment',   'Peintre en bâtiment',       'peintre peinture badigeon', 4),
  ('batiment', 'plombier',           'Plombier',                  'plombier plomberie tuyauterie sanitaire', 5),
  ('batiment', 'electricien',        'Électricien bâtiment',      'electricien électricien elec courant installation', 6),
  ('batiment', 'menuisier-bois',     'Menuisier bois',            'menuisier bois ebeniste porte fenetre', 7),
  ('batiment', 'soudeur',            'Soudeur / Menuisier métal', 'soudeur soudure metallique fer forge', 8),
  ('batiment', 'charpentier',        'Charpentier',               'charpentier charpente toiture', 9),
  ('batiment', 'plaquiste',          'Plaquiste / Faux plafond',  'plaquiste placo faux plafond staff', 10),
  ('batiment', 'etancheur',          'Étancheur',                 'etancheur étanchéité toiture infiltration', 11),
  ('batiment', 'puisatier',          'Puisatier / Forage',        'puisatier puits forage eau', 12),
  ('batiment', 'terrassier',         'Terrassier',                'terrassier terrassement fouille excavation', 13),
  ('batiment', 'manoeuvre',          'Manœuvre',                  'manoeuvre manœuvre aide chantier ouvrier', 14),
  ('batiment', 'chef-chantier',      'Chef de chantier',          'chef chantier conducteur travaux', 15),
  ('batiment', 'vitrier',            'Vitrier / Aluminium',       'vitrier vitre alu aluminium miroiterie', 16),

  -- Transport
  ('transport', 'chauffeur-particulier','Chauffeur particulier',  'chauffeur prive particulier voiture', 1),
  ('transport', 'chauffeur-poids-lourd','Chauffeur poids lourd',  'chauffeur camion poids lourd remorque', 2),
  ('transport', 'chauffeur-taxi',    'Chauffeur taxi / VTC',      'taxi vtc chauffeur course', 3),
  ('transport', 'livreur-moto',      'Livreur à moto',            'livreur moto coursier zemidjan okada', 4),
  ('transport', 'demenageur',        'Déménageur',                'demenageur déménagement transport meuble', 5),
  ('transport', 'coursier',          'Coursier',                  'coursier livraison colis pli', 6),
  ('transport', 'conducteur-engin',  'Conducteur d''engin',       'engin pelle bulldozer tractopelle grue', 7),

  -- Maison
  ('maison', 'menage',               'Ménage / Entretien',        'menage ménage nettoyage femme de menage bonne', 1),
  ('maison', 'cuisinier-domicile',   'Cuisinier(ère) à domicile', 'cuisinier cuisiniere cuisine repas', 2),
  ('maison', 'garde-enfants',        'Garde d''enfants',          'nounou nourrice garde enfant baby sitter', 3),
  ('maison', 'repassage',            'Repassage / Blanchisserie', 'repassage linge blanchisserie lessive', 4),
  ('maison', 'aide-domicile',        'Aide à domicile',           'aide domicile personne agee assistance', 5),
  ('maison', 'laveur-vitres',        'Laveur de vitres',          'laveur vitre nettoyage vitrerie', 6),

  -- Réparation
  ('reparation', 'mecanicien-auto',  'Mécanicien auto',           'mecanicien mécanicien auto voiture garage', 1),
  ('reparation', 'mecanicien-moto',  'Mécanicien moto',           'mecanicien moto scooter deux roues', 2),
  ('reparation', 'frigoriste',       'Frigoriste / Climatisation','frigoriste clim climatisation froid frigo', 3),
  ('reparation', 'reparateur-electromenager','Réparateur électroménager','electromenager machine laver frigo television', 4),
  ('reparation', 'reparateur-telephone','Réparateur de téléphone','telephone portable smartphone ecran reparation', 5),
  ('reparation', 'informaticien',    'Dépannage informatique',    'informatique ordinateur pc reseau depannage', 6),
  ('reparation', 'antenniste',       'Antenniste / Parabole',     'antenne parabole canal decodeur satellite', 7),
  ('reparation', 'technicien-solaire','Technicien solaire',       'solaire panneau photovoltaique energie', 8),

  -- Espaces verts
  ('espaces-verts', 'jardinier',     'Jardinier',                 'jardinier jardin gazon pelouse plantes', 1),
  ('espaces-verts', 'elagueur',      'Élagueur',                  'elagueur élagage arbre abattage', 2),
  ('espaces-verts', 'ouvrier-agricole','Ouvrier agricole',        'agricole champ plantation recolte', 3),
  ('espaces-verts', 'eleveur',       'Aide éleveur',              'eleveur elevage betail volaille berger', 4),

  -- Sécurité
  ('securite', 'gardien',            'Gardien',                   'gardien gardiennage garde maison', 1),
  ('securite', 'vigile',             'Vigile / Agent de sécurité','vigile agent securite surveillance', 2),
  ('securite', 'veilleur-nuit',      'Veilleur de nuit',          'veilleur nuit ronde surveillance nocturne', 3),

  -- Artisanat
  ('artisanat', 'couturier',         'Couturier(ère)',            'couturier couturiere couture tailleur habit', 1),
  ('artisanat', 'coiffeur',          'Coiffeur / Coiffeuse',      'coiffeur coiffeuse coiffure tresse barbier', 2),
  ('artisanat', 'cordonnier',        'Cordonnier',                'cordonnier chaussure reparation cuir', 3),
  ('artisanat', 'tapissier',         'Tapissier',                 'tapissier fauteuil canape rembourrage', 4),
  ('artisanat', 'ebeniste',          'Ébéniste',                  'ebeniste meuble bois sur mesure', 5),

  -- Événementiel
  ('evenementiel', 'traiteur',       'Traiteur',                  'traiteur cuisine evenement buffet', 1),
  ('evenementiel', 'serveur',        'Serveur / Serveuse',        'serveur serveuse service table restauration', 2),
  ('evenementiel', 'decorateur',     'Décorateur événementiel',   'decorateur decoration mariage salle', 3),
  ('evenementiel', 'sonorisateur',   'Sonorisation / DJ',         'sono sonorisation dj musique enceinte', 4),
  ('evenementiel', 'photographe',    'Photographe / Vidéaste',    'photographe photo video cameraman', 5)
) as v(cat_slug, slug, name_fr, search_terms, sort_order)
join public.trade_categories c on c.slug = v.cat_slug;

-- =====================================================================
-- EMPLACEMENTS PUBLICITAIRES
--
-- Remplace les identifiants ca-app-pub-XXX par les tiens depuis la
-- console AdMob. Ceux ci-dessous sont les ID de TEST officiels Google :
-- ne publie jamais avec ces valeurs, mais ne teste jamais avec les tiens
-- non plus (clics sur tes propres pubs = suspension du compte AdMob).
-- =====================================================================
insert into public.ad_placements
  (key, format, ad_unit_android, is_enabled, reward_credits, daily_cap_per_user, min_seconds_between, description)
values
  ('unlock_contact_rewarded', 'rewarded', 'ca-app-pub-3940256099942544/5224354917',
    true, 1, 8, 30,
    'Opt-in explicite : "Regarder une vidéo pour débloquer ce contact". Meilleur eCPM du catalogue.'),

  ('boost_profile_rewarded', 'rewarded', 'ca-app-pub-3940256099942544/5224354917',
    true, 0, 2, 300,
    'Opt-in explicite : met le profil de l''ouvrier en avant 6 h. Sert la rétention autant que le revenu.'),

  ('job_list_banner', 'banner', 'ca-app-pub-3940256099942544/6300978111',
    true, 0, null, 0,
    'Bannière en bas de la liste des demandes. eCPM faible mais volume constant.'),

  ('profile_view_interstitial', 'interstitial', 'ca-app-pub-3940256099942544/1033173712',
    true, 0, 5, 180,
    'Entre deux écrans seulement, après 3 profils consultés. Jamais pendant une action.'),

  ('app_open', 'app_open', 'ca-app-pub-3940256099942544/9257395921',
    false, 0, 3, 600,
    'Au retour dans l''app, jamais au tout premier lancement. Désactivé par défaut.');

-- =====================================================================
-- CONTRÔLE
-- =====================================================================
select c.name_fr as categorie, count(t.id) as nb_metiers
  from public.trade_categories c
  left join public.trades t on t.category_id = c.id
 group by c.id, c.name_fr, c.sort_order
 order by c.sort_order;
