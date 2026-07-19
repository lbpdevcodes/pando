# frozen_string_literal: true

Pando::Application.routes do
  root "chat#show", title: "Chats"
  screen "/onboarding", to: "onboarding#show", title: "Unlock"
end
