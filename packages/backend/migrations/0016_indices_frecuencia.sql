-- Migration number: 0016 	 2026-09-27T00:00:04.000Z

-- Indices for the frequency prize count.
--
-- Counting how many approved purchases a user made at a sponsor's business
-- scans one table: facturas, filtered by user, by approval state and by
-- business, and then narrowed down to the window of the round or the event.
-- Without an index D1 has to walk every invoice of every user on each claim.

-- The column order follows how the query filters: cliente_id first, because it
-- is the most selective and always present; estado second, because it discards
-- most of the rows quickly; comercio_id third, because it is the last filter
-- before the date window. comercio_id is included rather than left out of the
-- index so the count can be answered from the index alone in the common case
-- where the window covers whole days.
CREATE INDEX IF NOT EXISTS idx_facturas_cliente_estado_comercio
  ON facturas (cliente_id, estado, comercio_id);

-- Reaching a prize's window goes from the event to its rounds. Without this,
-- finding a round's hours means scanning the rounds of every event. The claim
-- path also looks the prize up by event, so evento_id leads the index.
CREATE INDEX IF NOT EXISTS idx_premios_evento_ronda
  ON premios (evento_id, ronda_id);

-- Deliberately NOT indexed, because an existing constraint already covers the
-- lookup the count needs:
--
--   eventos_sponsors  the count asks whether a business sponsors an event, by
--                     the pair (evento_id, comercio_id). The UNIQUE on that
--                     same pair already creates an index with those columns.
--
--   premios_entregados  the claim asks whether the user already took a prize in
--                     the round, by (usuario_id, ronda_id). The UNIQUE on that
--                     same pair already covers it, and it is also what keeps a
--                     user from taking two prizes in one round.
