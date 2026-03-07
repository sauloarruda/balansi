class RodauthApp < Rodauth::Rails::App
  configure RodauthMain

  route do |r|
    rodauth.load_memory

    r.rodauth
  end
end
