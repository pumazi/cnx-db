-- ###
-- Copyright (c) 2013, Rice University
-- This software is subject to the provisions of the GNU Affero General
-- Public License version 3 (AGPLv3).
-- See LICENCE.txt for details.
-- ###
SELECT
  module_ident,
  %({0})s::text||'-::-maintainer' as key
FROM
  latest_modules AS m,
  users AS u
WHERE
  u.username = ANY (m.maintainers)
  AND
  (u.first_name ~* req(%({0})s::text)
   OR
   u.last_name ~* req(%({0})s::text)
   OR
   u.full_name ~* req(%({0})s::text)
   OR
   u.username ~* req(%({0})s::text)
   )
