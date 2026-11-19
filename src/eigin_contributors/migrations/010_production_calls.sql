ALTER TABLE call_selections DROP CONSTRAINT call_selections_mode_check,
  ADD CHECK (mode IN ('rehearsal', 'production'));
ALTER TABLE call_publications DROP CONSTRAINT call_publications_mode_check,
  ADD CHECK (mode IN ('rehearsal', 'production'));
