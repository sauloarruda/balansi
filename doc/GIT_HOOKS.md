# Git Pre-Commit Hook - RuboCop Linting

## Overview

Um git pre-commit hook foi configurado para executar automaticamente o RuboCop com autocorrect antes de cada commit. Isso garante que:

1. **Autocorrect**: Erros de lint são automaticamente corrigidos pelo RuboCop
2. **Re-staging**: Os arquivos corrigidos são automaticamente adicionados ao stage
3. **Validação**: Se erros forem encontrados após o autocorrect, o commit é bloqueado

## Como Funciona

Quando você tenta fazer commit, o hook:

1. Identifica todos os arquivos Ruby (.rb) e Slim (.slim) em stage
2. Executa `rubocop --autocorrect-all` nesses arquivos
3. Re-adiciona os arquivos corrigidos ao stage
4. Executa `rubocop` novamente para validar que não há mais erros
5. Se ainda houver erros, o commit é bloqueado com uma mensagem de erro clara

## Instalação Manual

Se por algum motivo o hook não estiver instalado, você pode instalá-lo manualmente:

```bash
chmod +x script/pre-commit-hook.sh
cp script/pre-commit-hook.sh .git/hooks/pre-commit
```

Ou execute o script de setup:

```bash
bin/setup
```

## Desvio do Hook (Bypass)

Se necessário, você pode fazer bypass do hook usando a flag `--no-verify`:

```bash
git commit --no-verify
```

⚠️ **Use com cautela!** Isso pode permitir que erros de lint sejam commitados.

## Verificação Manual

Para verificar erros de lint manualmente:

```bash
# Ver todos os erros
bundle exec rubocop

# Autocorrigir erros automaticamente
bundle exec rubocop --autocorrect-all

# Verificar apenas um arquivo
bundle exec rubocop app/models/user.rb
```

## Troubleshooting

### Hook não está sendo executado

Verifique se o arquivo é executável:

```bash
ls -la .git/hooks/pre-commit
```

Se não for, corrija as permissões:

```bash
chmod +x .git/hooks/pre-commit
```

### RuboCop não está encontrado

Certifique-se de que todas as dependências estão instaladas:

```bash
bundle install
```

### Arquivos não estão sendo adicionados

O hook assumira que o `git` está disponível e o repositório está inicializado. Verifique o status do repositório:

```bash
git status
```
