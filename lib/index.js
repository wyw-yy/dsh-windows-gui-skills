/**
 * dsh-windows-gui-skills — adapter entry.
 *
 * The bundle ships four Agent Skills and nothing else: no tools, no client
 * code, no network. This module only exposes a helper that resolves the
 * packaged `skills/` directory, which `cordis.patch.yml` points the DSH Skill
 * loader at. The YAML patch resolves the same path from the profile baseUrl,
 * so this helper is what a host (or a test) calls when it already has one.
 */
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';

export const name = 'windows-gui-skills-dsh';
export const PACKAGE_NAME = 'dsh-windows-gui-skills';
export const SKILL_NAMES = [
  'windows-gui-control',
  'windows-screen-automation',
  'windows-uia-inspector',
  'windows-input-bridge',
];

/**
 * @param {string} profileBaseUrl  DSH profile base URL (or any path inside it)
 * @returns {string} absolute path to this package's `skills/` directory
 */
export function resolveSkillRoot(profileBaseUrl) {
  if (!profileBaseUrl) {
    throw new Error('dsh-windows-gui-skills: missing DSH profile baseUrl for package resolution');
  }
  let manifestPath;
  try {
    manifestPath = createRequire(profileBaseUrl).resolve(`${PACKAGE_NAME}/package.json`);
  } catch (error) {
    throw new Error(
      `dsh-windows-gui-skills: cannot resolve ${PACKAGE_NAME}/package.json from the DSH profile`,
      { cause: error },
    );
  }
  return join(dirname(manifestPath), 'skills');
}
