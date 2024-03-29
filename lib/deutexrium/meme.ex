defmodule Deutexrium.Meme do
  @moduledoc "Generates memes"

  alias Deutexrium.Server.Channel

  @templates [
    :gif_caption,
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
    },
    %{
      template: "mike_wazowski.png",
      images: [],
      text: [
        %{font: "Noto-Sans-Bold", geometry: "884x139+99+56", color: "black"}
      ]
    },
    %{
      template: "starter_pack.png",
      images: [
        "209x206!+34+104",
        "256x189!+383+242",
        "148x154!+276+94",
        "212x196!+1+397",
        "145x126!+271+441",
      ],
      text: [
        %{font: "Noto-Sans-Bold", geometry: "263x76+10+4", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "206x53+36+319", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "112x95+273+254", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "220x59+415+424", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "205x33+1+592", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "174x54+255+569", color: "black"}
      ]
    },
    %{
      template: "choose_your_class.png",
      images: [
        "180x140!+27+98",
        "180x140!+260+95",
        "180x140!+481+95",
        "180x140!+23+312",
        "180x140!+254+312",
        "180x140!+476+312"
      ],
      text: [
        %{font: "Noto-Sans-Bold", geometry: "185x35+25+243", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "185x35+256+243", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "185x35+479+244", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "185x35+22+457", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "185x35+250+457", color: "black"},
        %{font: "Noto-Sans-Bold", geometry: "185x35+474+457", color: "black"}
      ]
    },
    %{
      template: "text_msg.png",
      images: [],
      text: [
        %{font: "Noto-Sans-Bold", geometry: "411x71+326+297", color: "white"},
        %{font: "Noto-Sans-Bold", geometry: "420x127+101+479", color: "black"}
      ]
    }
  ]

  def extract_gif(url, path) do
    # download
    {_, 0} = System.cmd("wget", ["-O", path, "--", url],
      env: [{"DEUTEX_TOKEN", ""}], stderr_to_stdout: true)

    case File.read!(path) do
      <<"GIF87a", _ :: binary>> -> :ok
      <<"GIF89a", _ :: binary>> -> :ok
      html ->
        document = Floki.parse_document!(html)
        # extract actual gif url
        [{"meta", [_, _, {"content", url}], []}] =
          Floki.find(document, "meta[property=\"og:image\"]")
        extract_gif(url, path)
    end
  end

  @spec generate({integer(), integer()}, integer()) :: Path.t
  def generate(channel, unique_id) do
    # choose template
    template_n = :rand.uniform(length(@templates)) - 1

    # prepare temporary path
    root = System.tmp_dir! |> Path.join("#{unique_id}")
    File.mkdir(root)

    generate_from_template(channel, root, @templates |> Enum.at(template_n))
  end

  def generate_from_template(channel, root, :gif_caption) do
    meme_path = root |> Path.join("output.gif")

    # get gifs
    uri_list = Channel.get_files(channel)
      |> Enum.filter(fn uri -> String.match?(uri.path, ~r/gif/) or uri.host == "tenor.com" end)
      |> Enum.map(fn uri ->
        str = URI.to_string(uri)
        if String.ends_with?(str, ".gif") do str else str <> ".gif" end
      end)

    # select random gif
    n = :rand.uniform(length(uri_list)) - 1
    uri = uri_list |> Enum.at(n)

    # download gif
    dl_target = Path.join(root, "output.gif")
    extract_gif(uri, dl_target)

    # query size
    {sizes, 0} = System.cmd("magick", [
      "identify",
      "-format", "%[fx:w]x%[fx:h].",
      dl_target], env: [{"DEUTEX_TOKEN", ""}])
    [w, h] = String.split(sizes, ".") |> Enum.at(0) |> String.split("x")
    {h, _} = Integer.parse(h)
    h = floor(h / 4)

    # generate text
    text_path = Path.join(root, "text.png")
    {text, _} = Channel.generate(channel)
    {_, 0} = System.cmd("magick", [
      "-background", "transparent",
      "-fill", "white",
      "-stroke", "black",
      "-strokewidth", "2",
      "-font", "Noto-Sans-Bold",
      "-size", "#{w}x#{h}^",
      "-gravity", "center",
      "caption:#{text}",
      text_path], env: [{"DEUTEX_TOKEN", ""}], stderr_to_stdout: true)

    # overlay text
    {_, 0} = System.cmd("magick", [
      "convert", dl_target,
      "-coalesce",
      "null:", text_path,
      "-gravity", "north",
      "-layers", "composite",
      "-layers", "optimize",
      meme_path], env: [{"DEUTEX_TOKEN", ""}], stderr_to_stdout: true)

    meme_path
  end

  def generate_from_template(channel, root, template_spec) do
    template_path = :code.priv_dir(:deutexrium)
      |> Path.join("meme_templates")
      |> Path.join(template_spec.template)
    meme_path = root |> Path.join(["output", Path.extname(template_path)])
    File.cp(template_path, meme_path)

    # overlay images
    uri_list = Channel.get_files(channel, ~r/jpg|jpeg|png|webp/)
    for geometry <- template_spec.images do
      # select random image
      n = :rand.uniform(length(uri_list)) - 1
      uri = uri_list |> Enum.at(n)
      dl_target = Path.join(root, "overlay")
      {_, 0} = System.cmd("wget", ["-O", dl_target, "--", uri |> URI.to_string],
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
