# -*- coding: utf-8 -*-
from cnxdb.cli.discovery import register_subcommand


@register_subcommand('module1-command')
def command(args):
    return True
