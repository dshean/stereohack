#! /usr/bin/env python

#David Shean
#dshean@gmail.com

#Simple tool to calculate area elevation distribution (AKA hypsometry)
#Inputs should be DEM and polygon.shp for clipping
#Outputs plot and csv

#TODO: What text file formatting does USGS expect? 
#TODO: histogram bar plot rather than line plot, clean up map

import sys
import os
import argparse

import numpy as np
import matplotlib.pyplot as plt

from pygeotools.lib import iolib
from pygeotools.lib import malib
from pygeotools.lib import geolib

#Compute area-elevation distribution for give bin height in m
def aed(dem, res=None, bin_width=100.0):
    #Define min and max elevation
    minz, maxz= list(malib.calcperc(dem, perc=(0.01, 99.99)))
    minz = np.floor(minz/bin_width) * bin_width
    maxz = np.ceil(maxz/bin_width) * bin_width
    #Compute bin edges and centers
    bin_edges = np.arange(minz, maxz + bin_width, bin_width)
    bin_centers = bin_edges[:-1] + np.diff(bin_edges)/2.0
    #Compress masked array to get only valid elevations
    demc = dem.compressed()
    #Compute histogram
    bin_counts, bin_edges = np.histogram(demc, bins=bin_edges)
    #Convert count to area
    bin_areas = bin_counts * res * res / 1E6
    return bin_centers, bin_areas

def plot_aed(bin_centers, bin_areas):
    f,ax = plt.subplots()
    ax.plot(bin_centers, bin_areas)
    ax.set_xlabel('Elevation (m WGS84)')
    ax.set_ylabel('Area $\mathregular{km^2}$')
    plt.show()

#Generate two-panel plot with DEM map and AED
def plot_dem_aed(dem, bin_centers, bin_areas):
    f,axa = plt.subplots(2)
    axa[0].imshow(dem)
    axa[1].plot(bin_centers, bin_areas)
    axa[1].set_xlabel('Elevation (m WGS84)')
    axa[1].set_ylabel('Area $\mathregular{km^2}$')
    plt.show()

def write_aed(bincenters, count, out_fn=None):
    if out_fn is None:
        out_fn = 'aed.csv'
    header='bin_center_m,bin_area_km2'
    np.savetxt(out_fn, zip(bincenters, count), fmt='%0.1f', delimiter=',', header=header)

def main():
    parser = argparse.ArgumentParser(description="Utility to compute hypsometry for input DEM")
    parser.add_argument('-mask_fn', type=str, default=None, help='Glacier Polygon filename (mask.shp)')
    parser.add_argument('-bin_width', type=float, default=100.0, help='Elevation bin with (default: %(default)s)')
    parser.add_argument('dem_fn', type=str, help='Input DEM filename')
    args = parser.parse_args()

    #Input DEM
    dem_fn = args.dem_fn
    #Extract GDAL dataset from input dem_fn
    dem_ds = iolib.fn_getds(dem_fn)
    #Extract NumPy masked array from dem_ds
    print("Loading input DEM: %s" % args.dem_fn)
    dem = iolib.ds_getma(dem_ds)
    #Fill dem?
    #Extract DEM resolution (m)
    dem_res = geolib.get_res(dem_ds, square=True)[0]

    #Generate glacier mask from shp 
    if args.mask_fn is not None:
        print("Masking input DEM using: %s" % args.mask_fn)
        #This calls gdal_rasterize with parameters of dem_ds
        mask = geolib.shp2array(args.mask_fn, r_ds=dem_ds)
        #Apply mask to DEM
        dem = np.ma.array(dem, mask=mask)

    #Generate aed 
    print("Generating AED")
    bin_centers, bin_areas = aed(dem, dem_res, args.bin_width) 
    #Write out to csv
    csv_fn = os.path.splitext(dem_fn)[0]+'_aed.csv'
    write_aed(bin_centers, bin_areas, csv_fn)
    #Generate plot
    plot_dem_aed(dem, bin_centers, bin_areas)
    #plot_aed(bin_centers, bin_areas)

if __name__ == "__main__":
    main()
