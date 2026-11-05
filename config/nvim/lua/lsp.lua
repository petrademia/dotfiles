-- Language servers through Neovim's built-in LSP client (no plugins). Setup installs the servers;
-- a server is only enabled when its binary is on PATH, so a machine without one stays quiet.

vim.lsp.config("gopls", {
  cmd = { "gopls" },
  filetypes = { "go", "gomod", "gowork", "gotmpl" },
  root_markers = { "go.work", "go.mod", ".git" },
})

vim.lsp.config("clangd", {
  cmd = { "clangd" },
  filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
  root_markers = { "compile_commands.json", "compile_flags.txt", ".clangd", ".git" },
})

-- jdtls keeps project state in a workspace directory that must be unique per project.
vim.lsp.config("jdtls", {
  cmd = function(dispatchers, config)
    local root = config.root_dir or vim.fn.getcwd()
    local workspace = vim.fn.stdpath("cache") .. "/jdtls/" .. vim.fn.fnamemodify(root, ":t") .. "-" .. vim.fn.sha256(root):sub(1, 8)
    return vim.lsp.rpc.start({ "jdtls", "-data", workspace }, dispatchers, {
      cwd = config.cmd_cwd,
      env = config.cmd_env,
    })
  end,
  filetypes = { "java" },
  root_markers = { "gradlew", "mvnw", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", ".git" },
})

for server, binary in pairs({ gopls = "gopls", clangd = "clangd", jdtls = "jdtls" }) do
  if vim.fn.executable(binary) == 1 then
    vim.lsp.enable(server)
  end
end

-- Neovim already maps K (hover), grn (rename), gra (code action), grr (references) and gri
-- (implementation) while a server is attached; these fill the gaps.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
    end
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("<leader>f", function() vim.lsp.buf.format({ async = true }) end, "Format buffer")
    map("<leader>e", vim.diagnostic.open_float, "Show diagnostic")
  end,
})
