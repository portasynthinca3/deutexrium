defmodule Deutexrium.Meme do
  @moduledoc "Generates memes"

  alias Deutexrium.Server.Channel

  @templates [
    %{
      template: "demotivator.png",
      images: [
        "540x358!+59+58"
      ],
      text: [
        %{font: "Linux-Libertine", geometry: "554x65+52+430", color: "white"},
        %{font: "Linux-Libertine", geometry: "554x87+52+505", color: "white"}
      ]
    },
    %{
      template: "drake.png",
      images: [],
      text: [
        %{font: "Noto-Sans-Bold", geometry: "493x473+653+69", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "493x473+653+666", color: "black"}
      ]
    },
    %{
      template: "cmon_do_something.png",
      images: [
        "327x314!+361+314"
      ],
      text: [
        %{font: "Noto-Sans-Bold", geometry: "424x93+256+203", color: "black"}
      ]
    },
    %{
      template: "who_would_win.png",
      images: [
        "408x317!+9+111",
        "393x297!+442+115"
      ],
      text: [
        %{font: "Noto-Sans-Bold", geometry: "407x61+10+457", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "400x61+436+458", color: "black"}
      ]
    }
  ]

  @spec generate({integer(), integer()}, integer()) :: Path.t
  def generate(channel, unique_id) do
    # choose template
    template_n = :rand.uniform(length(@templates)) - 1
    template_spec = @templates |> Enum.at(template_n)

    # prepare temporary path
    root = System.tmp_dir! |> Path.join("#{unique_id}")
    File.mkdir(root)
    template_path = :code.priv_dir(:deutexrium)
      |> Path.join("meme_templates")
      |> Path.join(template_spec.template)
    meme_path = root |> Path.join(["output", Path.extname(template_path)])
    File.cp(template_path, meme_path)

    # overlay images
    for geometry <- template_spec.images do
      # get image to overlay
      url = Channel.get_file(channel, ~r/jpg|jpeg|png|webp/)
      dl_target = Path.join(root, "overlay")
      {_, 0} = System.cmd("wget", ["-O", dl_target, "--", url],
        env: [{"DEUTEX_TOKEN", ""}], stderr_to_stdout: true) # i'm sure wget isn't malicious but..

      # overlay image
      {_, 0} = System.cmd("magick", [
        "composite", dl_target, meme_path,
        "-geometry", geometry,
        meme_path], env: [{"DEUTEX_TOKEN", ""}], stderr_to_stdout: true)
    end

    # generate and overlay text
    for config <- template_spec.text do
      # get text options
      {text, _} = Channel.generate(channel)
      text_path = Path.join(root, "text.png")
      [width, height] = String.split(config.geometry, "x", parts: 2)

      # generate text
      {_, 0} = System.cmd("magick", [
        "-background", "transparent",
        "-fill", config.color,
        "-font", config.font,
        "-size", "#{width}x#{height}^",
        "-gravity", "center",
        "caption:#{text}",
        text_path], env: [{"DEUTEX_TOKEN", ""}], stderr_to_stdout: true)

      # overlay text
      {_, 0} = System.cmd("magick", [
        "composite", text_path, meme_path,
        "-geometry", config.geometry,
        meme_path], env: [{"DEUTEX_TOKEN", ""}], stderr_to_stdout: true)
    end

    meme_path
  end

  def cleanup(output_path), do: Path.dirname(output_path) |> File.rm_rf!
end
