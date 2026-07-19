# frozen_string_literal: true

module Pando
  module Layouts
    class ApplicationLayout < Charming::View
      def render
        screen_layout(background: theme.background) do
          split(narrow? ? :vertical : :horizontal, gap: 1) do
            pane(:sidebar, **sidebar_options, border: :rounded, padding: [1, 2], style: sidebar_style) do
              column(app_title, sidebar_body, shortcuts, gap: 1)
            end

            pane(:content, grow: 1, border: :rounded, padding: [1, 2], style: content_style) do
              yield_content
            end
          end

          overlay add_contact_modal if add_contact_modal
          overlay generic_modal if generic_modal
          overlay command_palette_modal if command_palette_modal
          overlay help_modal, z_index: 5 if help_modal
          overlay toast, top: screen.height - 5, left: :center, z_index: 10 if toast
        end
      end

      def add_contact_modal
        input = assigns.fetch(:add_contact, nil)
        return unless input

        render_component Charming::Components::Modal.new(
          title: "Add contact", content: render_component(input),
          help: "enter add · esc cancel", theme: theme
        )
      end

      # Controllers open one modal at a time through the :modal assign —
      # {title:, content:, help:} with content either a component or plain text.
      def generic_modal
        spec = assigns.fetch(:modal, nil)
        return unless spec

        content = spec[:content]
        content = render_component(content) if content.respond_to?(:render)
        render_component Charming::Components::Modal.new(
          title: spec[:title], content: content, help: spec[:help], theme: theme
        )
      end

      private

      def help_modal
        return unless controller.session[:help_open]

        render_component controller.help_overlay
      end

      def toast
        toast_state = controller.session[:toast]
        return unless toast_state

        render_component Charming::Components::Toast.new(
          message: toast_state[:message],
          kind: toast_state.fetch(:kind, :info),
          theme: theme
        )
      end

      def palette_component
        assigns.fetch(:palette, nil)
      end

      def narrow?
        screen.narrow?(below: 72, min_height: 20)
      end

      def sidebar_options
        narrow? ? {height: [screen.height / 3, 5].max} : {width: 22}
      end

      def sidebar_inner_width
        narrow? ? [screen.width - 6, 20].max : 16
      end

      def app_title
        text "Pando", style: theme.header_accent.align(:center).width(sidebar_inner_width)
      end

      # Controllers may hand the sidebar a component (the chat conversation list);
      # without one, the route navigation renders as generated.
      def sidebar_body
        component = assigns.fetch(:sidebar, nil)
        component ? render_component(component) : navigation
      end

      def navigation
        column(*nav_items)
      end

      def nav_items
        controller.sidebar_routes.each_with_index.map do |route, index|
          text nav_item_label(route, index), style: nav_item_style(route, index)
        end
      end

      def nav_item_label(route, index)
        cursor = (sidebar_focused? && index == sidebar_index) ? ">" : " "
        active = current_route?(route) ? "\u{25cf}" : " "
        "#{cursor} #{active} #{route.title}"
      end

      def nav_item_style(route, index)
        if sidebar_focused? && index == sidebar_index
          theme.selected
        elsif current_route?(route)
          theme.title
        else
          theme.muted
        end
      end

      def shortcuts
        text "tab focus\nctrl+p commands\n? help\nq quit", style: theme.muted
      end

      def sidebar_style
        focused_style = sidebar_focused? ? theme.title : theme.border
        palette_component ? focused_style.faint : focused_style
      end

      def content_style
        focused_style = content_focused? ? theme.title : theme.border
        palette_component ? focused_style.faint : focused_style
      end

      def command_palette_modal
        return unless palette_component

        render_component Charming::Components::CommandPaletteModal.new(
          content: palette_component,
          theme: theme
        )
      end

      def sidebar_focused?
        controller.sidebar_focused?
      end

      def content_focused?
        controller.content_focused?
      end

      def sidebar_index
        controller.sidebar_index
      end

      def current_route?(route)
        controller.current_route?(route)
      end
    end
  end
end
