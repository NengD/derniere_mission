"""Installe les paquets de ressources officiels de MakeHuman dans les données utilisateur de MPFB,
comme le bouton « Load pack from zip file » de l'interface de MPFB, mais en ligne de commande.

Prérequis : l'extension MPFB installée dans Blender (une seule fois) :
    blender --command extension install-file --repo user_default --enable _sources/mpfb/addon/add-on-mpfb-v2.0.18.zip
    (archive officielle : https://extensions.blender.org/add-ons/mpfb/)

Usage : blender -b --factory-startup -P tools/blender/install_mpfb_packs.py
        -> installe toutes les archives _sources/mpfb/<paquet>/<paquet>*.zip (sauf l'extension elle-même)

Paquets officiels utilisés (https://static.makehumancommunity.org/assets/assetpacks.html) :
makehuman_system_assets (CC0), skins02 (CC0), shirts01 (CC0), shirts02/03 (CC-BY), pants01 (CC0),
pants02 (CC-BY), shoes01 (CC0), shoes02 (CC-BY), hats03 (CC-BY), masks01 (CC0), masks02 (CC-BY),
equipment03 (CC-BY). Auteurs et licences de chaque objet utilisé : CREDITS.md.
"""
import bpy
import addon_utils
import glob
import os
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MODULE = "bl_ext.user_default.mpfb"


def activer_mpfb():
    """--factory-startup désactive les extensions : on réactive MPFB pour cette session seulement."""
    if MODULE not in {m.__name__ for m in addon_utils.modules()} or not addon_utils.check(MODULE)[1]:
        bpy.ops.preferences.addon_enable(module=MODULE)
    import importlib
    return importlib.import_module(MODULE)


def main():
    activer_mpfb()
    from bl_ext.user_default.mpfb.services import LocationService, AssetService
    data_dir = LocationService.get_user_data()
    print("Données utilisateur MPFB :", data_dir)
    zips = [z for z in sorted(glob.glob(os.path.join(ROOT, "_sources", "mpfb", "*", "*.zip")))
            if os.path.basename(os.path.dirname(z)) != "addon"]
    for z in zips:
        with zipfile.ZipFile(z) as zf:
            # sécurité : aucun chemin absolu ni remontée de dossier dans l'archive
            bad = [n for n in zf.namelist() if n.startswith(("/", "\\")) or ".." in n.replace("\\", "/").split("/")]
            if bad:
                print("ARCHIVE REFUSEE", z, bad[:3])
                continue
        check = AssetService.check_asset_pack_zip(z)
        if check is not None:
            print("Archive à corriger :", z, check)
            res = AssetService.fix_and_extract_asset_pack_zip(z, data_dir)
            print("  correction :", res)
        else:
            with zipfile.ZipFile(z) as zf:
                zf.extractall(data_dir)
        print("INSTALLE", os.path.basename(z))
    AssetService.update_all_asset_lists()
    print("FIN", len(zips), "paquets")


main()
