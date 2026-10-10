-- Seed stazioni/aeroporti principali mancanti (es. Milano Centrale, Garibaldi, …).
-- Idempotente: inserisce solo nomi non già presenti (case-insensitive).

INSERT INTO public.stazioni (nome, attiva)
SELECT v.nome, true
FROM (
  VALUES
    ('Milano Centrale'),
    ('Milano Porta Garibaldi'),
    ('Milano Porta Garibaldi Sotterranea'),
    ('Milano Rogoredo'),
    ('Milano Lambrate'),
    ('Milano Greco Pirelli'),
    ('Milano Porta Genova'),
    ('Milano Cadorna'),
    ('Milano Nord Cadorna'),
    ('Milano Affori'),
    ('Milano Certosa'),
    ('Milano San Cristoforo'),
    ('Milano Porta Romana'),
    ('Milano Dateo'),
    ('Milano Repubblica'),
    ('Milano Villapizzone'),
    ('Milano Bovisa Politecnico'),
    ('Milano Nord Bovisa'),
    ('Milano Porta Vittoria'),
    ('Milano Forlanini'),
    ('Milano Porta Venezia'),
    ('Milano Domodossola'),
    ('Milano Lancetti'),
    ('Rho Fiera Milano'),
    ('Rho'),
    ('Monza'),
    ('Sesto San Giovanni'),
    ('Roma Termini'),
    ('Roma Tiburtina'),
    ('Roma Ostiense'),
    ('Torino Porta Nuova'),
    ('Torino Porta Susa'),
    ('Napoli Centrale'),
    ('Napoli Afragola'),
    ('Firenze Santa Maria Novella'),
    ('Bologna Centrale'),
    ('Venezia Santa Lucia'),
    ('Venezia Mestre'),
    ('Genova Piazza Principe'),
    ('Genova Brignole'),
    ('Verona Porta Nuova'),
    ('Padova'),
    ('Bari Centrale'),
    ('Palermo Centrale'),
    ('Catania Centrale'),
    ('Brescia'),
    ('Bergamo'),
    ('Como San Giovanni'),
    ('Parma'),
    ('Modena'),
    ('Reggio Emilia AV Mediopadana'),
    ('Macomer'),
    ('Cairo Montenotte')
) AS v(nome)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.stazioni s
  WHERE lower(trim(s.nome)) = lower(trim(v.nome))
);

INSERT INTO public.aeroporti (nome, attiva)
SELECT v.nome, true
FROM (
  VALUES
    ('Milano Malpensa'),
    ('Milano Linate'),
    ('Bergamo Orio al Serio'),
    ('Roma Fiumicino'),
    ('Roma Ciampino'),
    ('Venezia Marco Polo'),
    ('Napoli Capodichino'),
    ('Bologna Marconi'),
    ('Torino Caselle'),
    ('Firenze Peretola'),
    ('Pisa Galilei'),
    ('Genova Sestri'),
    ('Bari Palese'),
    ('Catania Fontanarossa'),
    ('Palermo Punta Raisi'),
    ('Cagliari Elmas')
) AS v(nome)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.aeroporti a
  WHERE lower(trim(a.nome)) = lower(trim(v.nome))
);
