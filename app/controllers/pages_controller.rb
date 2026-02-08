class PagesController < ApplicationController
  def home
    render inertia: "Home"
  end

  def docs
    render inertia: "Docs"
  end
end
