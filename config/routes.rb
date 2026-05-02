DiscourseOnesignal::Engine.routes.draw do
  post '/subscribe' => "onesignal#subscribe"
  get '/identity' => "onesignal#identity"
  get '/app-login' => "onesignal#app_login", format: :html
end
