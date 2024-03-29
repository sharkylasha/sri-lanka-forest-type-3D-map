
# language: R
##title: "Sri-Lanka-forest-type-3D-map"
##author: "Lashanthini Rajendram"
##date: "09/01/2024"


libs <- c(
  "giscoR", "terra", "elevatr","sf",
  "png", "rayshader", "magick"
  )

installed_libs <- libs %in% rownames(
  installed.packages()
)

if(any(installed_libs == F)){
  install.packages(
    libs[!installed_libs]
  )
}

invisible(lapply(
  libs, library,
  character.only = T
))


## 1. COUNTRY BOUNDARIES 
##----------------------------## ##https://lcviewer.vito.be/2019

country_sf <- giscoR::gisco_get_countries(
   country = "LK",
  resolution = "1"
)
 
## 2. FOREST TYPE RASTERS - 2019, CROP AND PROJECT THEM
##------------------------------------------------------##

urls <- c("https://s3-eu-west-1.amazonaws.com/vito.landcover.global/v3.0.1/2019/E060N20/E060N20_PROBAV_LC100_global_v3.0.1_2019-nrt_Forest-Type-layer_EPSG-4326.tif", "https://s3-eu-west-1.amazonaws.com/vito.landcover.global/v3.0.1/2019/E080N20/E080N20_PROBAV_LC100_global_v3.0.1_2019-nrt_Forest-Type-layer_EPSG-4326.tif")

for(url in urls){
  download.file(
    url = url,
    destfile = basename(url),
    mode = "wb"
  )
}

raster_files <- list.files(
  path = getwd(),
  pattern = "tif",
  full.names = T
)

crs <- "EPSG:4326"

for(raster in raster_files){
  rasters <- terra::rast(raster)
  
  country <- country_sf |>
    sf::st_transform(
      crs = terra::crs(
        rasters
      )
    )
  
  country_forest_type <- terra::crop(
    rasters,
    terra::vect(
      country
    ),
    snap ="in",
    mask = T
  ) |>
    terra::aggregate(
      fact = 5,
      fun = "modal"
    )|>
    terra::project(crs)
  
  terra::writeRaster(
    country_forest_type,
    paste0(
      raster,
      "_srilanka",
      ".tiff"
    )
  )
}


## 3. LOAD VIRTUAL FILES ##
##-----------------------##

r_list <- list.files(
  path = getwd(),
  pattern = "_srilanka",
  full.names = T
)

forest_type_vrt <- terra::vrt(
  r_list,
  "srilanka_land_cover_vrt.vrt",
  overwrite =T
)

vals <- terra::values(
  forest_type_vrt,
  dataframe = T
)

names(vals)

names(vals)[1] <- "value"

unique(vals$value)

## 4. CROP FOREST TYPE RASTER ##
#------------------------------------##
##Transverse Mercator Projection for local map system EPSG:5235

crs_tmercator <- 
  "+proj=tmerc +lat_0=7.00047152777778 +lon_0=80.7717130833333 +k=0.9999238418 +x_0=500000 +y_0=500000 +ellps=evrst30 +towgs84=-0.293,766.95,87.713,-0.195704,-1.695068,-3.473016,-0.039338 +units=m +no_defs +type=crs"

country_forest_type <- terra::crop(
  forest_type_vrt,
  terra::vect(country_sf),
  snap = "in",
  mask = T
)|>
  terra::project(crs_tmercator)


terra::plot(country_forest_type)

## 5.FOREST TYPE RASTER TO IMAGE ##
#----------------------------------##

cols <- c(
  "#C77CFF",
  "#ffcf6a",
  "#397d49",
  "#B22222",
  "#7cd8ff"
  
)


from <- c(0:2, 4:5)
to <- t(col2rgb(
  cols
))


forest_terra <- na.omit(
  country_forest_type
)

forest_type_raster <- terra::subst(
  forest_terra,
  from,
  to,
  names = cols
)

terra::plotRGB(forest_type_raster)

img_file <- "Sri-Lanka-forest-type-image.png"

terra::writeRaster(
  forest_type_raster,
  img_file,
  overwrite = T,
  NAflag = 255
)

img <- png::readPNG(img_file)

## 5. COUNTRY ELEVATION RASTER
##-----------------------------##

elev <- elevatr::get_elev_raster(
  locations = country_sf,
  z = 10,
  clip = "locations"
)

elev_tmercator <- elev |>
  terra::rast() |>
  terra::project(crs_tmercator)


elmat <- rayshader::raster_to_matrix(elev_tmercator)



## 6. RENDER SCENE ##
##------------------##

h <- nrow(elev_tmercator)
w <- nrow(elev_tmercator)


elmat |>
  rayshader::height_shade(
    texture = colorRampPalette(
      "white"
    )(700)
  ) |>
  rayshader::add_overlay(
    img,
    alphalayer = 0.9,
    alphacolor = "white"
  ) |>
  rayshader::add_shadow(
    rayshader::lamb_shade(
      elmat,
      zscale = 50,
      sunaltitude = 90,
      sunangle = 315
    ), max_darken = 0.25
  ) |>
  rayshader::add_shadow(
    rayshader::texture_shade(
      elmat,
      detail = 0.95,
      brightness = 90,
      contrast = 80,
    ), max_darken = 0.1
  ) |>
  rayshader::plot_3d(
    elmat,
    zscale = 5,
    solid = F,
    shadow = T,
    shadow_darkness = 1,
    background = "white",
    windowsize = c(
      w, h
    ),
    zoom = 0.5,
    phi = 85,
    theta = 0
  )

rayshader::render_camera(
  zoom = .58
)

## 7. RENDER OBJECT ##
##-------------------##

rayshader::render_highquality(
    filename = "SL-forest-type-3d.png",
    preview = T,
    light = F,
    environment_light = "air_museum_playground_4k.hdr",
    intensity_env = 2,
    rotate_env = 90,
    interactive = F,
    parallel = T,
    width = w/12, height = h/12
)


## 8. MAKE LEGEND #
##..................#

png("Forest_type_legend.png")
par(family = "mono")
plot(
    NULL, xaxt = "n",
    yaxt = "n", bty = "n",
    ylab = "", xlab = "",
    xlim = 0:1, ylim = 0:1,
    xaxs = "i", yaxs = "i"
)
legend(
    "center",
    legend = c(
        "Unknown",
        "Deciduous broad leaf",
        "Evergreen broad leaf",
        "Evergreen needle leaf",
        "Mixed"
    ),
    pch = 16,
    pt.cex = 3,
    cex = 1.5,
    bty = "n",
    col = cols
)
dev.off()


## 9. FINAL MAP ##
##---------------##


forest_img <- magick::image_read(
    "SL-forest-type-3d.png"
)

my_legend <- magick::image_read(
    "Forest_type_legend.png"
)

my_legend_scaled <- magick::image_scale(
    magick::image_background(
    my_legend, "none"), 2000
) |>
magick::image_transparent("white")

p <- magick::image_composite(
    magick::image_scale(
        forest_img,
        "x4000"
    ),
    my_legend_scaled,
    offset = "+100+0"
)

magick::image_write(
    p,
    "final-map.png"
)




